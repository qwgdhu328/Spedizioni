// favos_host.cpp — ponte C fra l'host Swift e la VM Favilla C++.
//
// La VM leva `Val (*)(int, const Val*)` senza contesto: ogni syscall
// registrata riceve un thunk dedicato (fav_thunk<I>) che sa lo slot e
// da lì il nome, poi chiama la callback Swift con valori FavVal.
// L'host corrente e' g_host, impostato per la durata di favhost_esegui.

#include "favos_vm.h"
#include "include/favos_host.h"

#include <stdlib.h>
#include <string.h>
#include <new>

#define FAV_HOST_MAX  48     // max syscalls registrabili (<= FAV_SYSCALLS_MAX)
#define FAV_POOL_N    128    // celle dei pool argomenti/risposta

struct FavHost {
    FavVM vm;
    void* utente;
    FavChiamata cb;
    char* nomi[FAV_HOST_MAX];
    int   n_nomi;
    uint8_t* buffer;         // copia privata del bytecode (la VM ci
    size_t   buffer_n;       // punta dentro: deve vivere con l'host)
    FavVal arg_pool[FAV_POOL_N];   // elementi liste degli argomenti
    int    arg_n;
    FavVal rep_pool[FAV_POOL_N];   // elementi liste della risposta
};

static FavHost* g_host = NULL;     // host della VM in esecuzione ora

static_assert(FAV_VAL_TESTO == FAV_TESTO_MAX,
              "FAV_VAL_TESTO deve coincidere con FAV_TESTO_MAX");

// ---------------------------------------------------------------
// Thunk: uno slot = un indirizzo C stabile per la VM
// ---------------------------------------------------------------
template <size_t... I> struct FavSeq {};
template <size_t N, size_t... I>
struct FavSeqBuild : FavSeqBuild<N - 1, N - 1, I...> {};
template <size_t... I>
struct FavSeqBuild<0, I...> { typedef FavSeq<I...> type; };

static Val fav_dispatch(int slot, int n, const Val* a);

template <size_t I>
static Val fav_thunk(int n, const Val* a) {
    return fav_dispatch((int)I, n, a);
}

template <size_t... I>
static void fav_popola(SyscallFn* out, FavSeq<I...>) {
    int k = 0;
    int unused[] = { (out[k++] = &fav_thunk<I>, 0)... };
    (void)unused;
}

static SyscallFn fav_thunk_slot(int i) {
    static SyscallFn tab[FAV_HOST_MAX];
    static bool pronto = false;
    if (!pronto) {
        memset(tab, 0, sizeof(tab));
        fav_popola(tab, typename FavSeqBuild<FAV_HOST_MAX>::type());
        pronto = true;
    }
    return tab[i];
}

// ---------------------------------------------------------------
// Conversioni Val <-> FavVal (profondita' massima 2)
// ---------------------------------------------------------------
static void fav_val_in(FavHost* h, const Val& v, FavVal* out, int prof) {
    memset(out, 0, sizeof(FavVal));
    if (v.tipo == TV_NUM) {
        out->tipo = 1; out->num = v.num;
    } else if (v.tipo == TV_TESTO) {
        out->tipo = 2;
        memcpy(out->testo, v.testo, FAV_VAL_TESTO - 1);
        out->testo[FAV_VAL_TESTO - 1] = 0;
    } else if (v.tipo == TV_LISTA && prof < 2) {
        out->tipo = 3;
        int n = h->vm.lista_n(v.li);
        if (n <= 0) { out->n_elementi = 0; return; }
        if (n > FAV_LISTA_MAX) n = FAV_LISTA_MAX;
        int posti = FAV_POOL_N - h->arg_n;
        if (n > posti) n = posti;
        if (n <= 0) return;
        FavVal* elem = &h->arg_pool[h->arg_n];
        h->arg_n += n;
        for (int i = 0; i < n; i++)
            fav_val_in(h, h->vm.lista_elem(v.li, i), &elem[i], prof + 1);
        out->elementi = elem;
        out->n_elementi = n;
    }
    // lista oltre la profondita' permessa: resta niente
}

static void fav_val_out(FavVM& vm, const FavVal* f, Val* out, int prof) {
    *out = Val::nulo();
    if (!f) return;
    if (f->tipo == 1) { *out = Val::numero(f->num); return; }
    if (f->tipo == 2) { *out = Val::stringa(f->testo); return; }
    if (f->tipo == 3 && prof < 2 && f->elementi) {
        Val items[FAV_LISTA_MAX];
        int n = f->n_elementi;
        if (n < 0) n = 0;
        if (n > FAV_LISTA_MAX) n = FAV_LISTA_MAX;
        for (int i = 0; i < n; i++)
            fav_val_out(vm, &f->elementi[i], &items[i], prof + 1);
        *out = vm.nuova_lista(n, items);
    }
}

// ---------------------------------------------------------------
// Dispatch: slot -> nome -> callback Swift -> risposta Val
// ---------------------------------------------------------------
static Val fav_dispatch(int slot, int n, const Val* a) {
    FavHost* h = g_host;
    Val risposta = Val::nulo();
    if (!h || !h->cb || slot < 0 || slot >= h->n_nomi || !h->nomi[slot])
        return risposta;

    h->arg_n = 0;
    FavVal arg[8];
    int m = n < 8 ? n : 8;
    for (int i = 0; i < m; i++)
        fav_val_in(h, a[i], &arg[i], 0);

    FavVal ris;
    memset(&ris, 0, sizeof(ris));
    h->cb(h->utente, h->nomi[slot], m, arg, &ris,
          h->rep_pool, FAV_POOL_N);

    fav_val_out(h->vm, &ris, &risposta, 0);
    return risposta;
}

// ---------------------------------------------------------------
// API C
// ---------------------------------------------------------------
FavHost* favhost_crea(void) {
    // value-init esplicita: azzera i campi POD e costruisce la FavVM
    FavHost* h = (FavHost*)malloc(sizeof(FavHost));
    if (!h) return NULL;
    new (h) FavHost();
    return h;
}

void favhost_distruggi(FavHost* h) {
    if (!h) return;
    for (int i = 0; i < h->n_nomi; i++) free(h->nomi[i]);
    free(h->buffer);
    h->vm.~FavVM();
    free(h);
}

void favhost_contesto(FavHost* h, void* utente, FavChiamata cb) {
    if (!h) return;
    h->utente = utente;
    h->cb = cb;
}

int32_t favhost_registra(FavHost* h, const char* nome) {
    if (!h || !nome || h->n_nomi >= FAV_HOST_MAX) return 0;
    if (h->n_nomi >= FAV_SYSCALLS_MAX) return 0;
    char* copia = strdup(nome);
    if (!copia) return 0;
    SyscallFn fn = fav_thunk_slot(h->n_nomi);
    if (!fn) { free(copia); return 0; }
    h->vm.registra(copia, fn);
    h->nomi[h->n_nomi++] = copia;
    return 1;
}

int32_t favhost_carica(FavHost* h, const uint8_t* dati, size_t n) {
    if (!h || !dati || n == 0) return 0;
    uint8_t* copia = (uint8_t*)malloc(n);
    if (!copia) return 0;
    memcpy(copia, dati, n);
    free(h->buffer);
    h->buffer = copia;
    h->buffer_n = n;
    return h->vm.carica(copia, n) ? 1 : 0;
}

void favhost_avvia(FavHost* h) {
    if (!h) return;
    h->vm.avvia();
}

int32_t favhost_esegui(FavHost* h, uint32_t istruzioni) {
    if (!h) return 0;
    FavHost* prec = g_host;
    g_host = h;
    bool vivo = h->vm.esegui_istanti(istruzioni);
    g_host = prec;
    return vivo ? 1 : 0;
}

int32_t favhost_ok(FavHost* h) {
    return (h && h->vm.ok) ? 1 : 0;
}

int32_t favhost_finito(FavHost* h) {
    return (h && h->vm.finito()) ? 1 : 0;
}

const char* favhost_errore(FavHost* h) {
    if (!h) return "host nullo";
    return h->vm.errore;
}
