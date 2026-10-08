// favos_vm.h — Macchina Virtuale Favilla in C++ (per ESP32 e PC)
//
// Esegue i file .fvb prodotti da favc.py. Solo C++11, zero STL.
// Le liste e i dizionari vivono in un pool fisso; se il pool si riempie
// parte un piccolo garbage collector mark-sweep (radici: stack + globali).
//
// Uso su PC (test rapido):
//     g++ -std=c++11 -o test_vm test_vm.cpp && ./test_vm app.fvb
// Uso su ESP32: compilato insieme a favos_esp32.ino.

#ifndef FAVOS_VM_H
#define FAVOS_VM_H

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdio.h>

// ---- dimensioni memoria (pensate per un ESP32 da 300+ KB di RAM) ----
#ifndef FAV_TESTO_MAX
#define FAV_TESTO_MAX 64     // lunghezza massima di una stringa
#endif
#ifndef FAV_MAX_COSTANTI
#define FAV_MAX_COSTANTI 256
#endif
#ifndef FAV_MAX_FUNZIONI
#define FAV_MAX_FUNZIONI 32
#endif
#ifndef FAV_MAX_GLOBALI
#define FAV_MAX_GLOBALI 96
#endif
#ifndef FAV_STIVA_MAX
#define FAV_STIVA_MAX 160
#endif
#ifndef FAV_FRAMES_MAX
#define FAV_FRAMES_MAX 12
#endif
#ifndef FAV_LISTE_MAX
#define FAV_LISTE_MAX 40     // quante liste/dict vivi al massimo
#endif
#ifndef FAV_LISTA_MAX
#define FAV_LISTA_MAX 32     // elementi per lista
#endif
#ifndef FAV_SYSCALLS_MAX
#define FAV_SYSCALLS_MAX 32  // quante syscalls puo' registrare l'host
#endif

// ---------------------------------------------------------------
// Valore dinamico
// ---------------------------------------------------------------
enum TipoVal { TV_NULO = 0, TV_NUM, TV_TESTO, TV_LISTA };

struct Val {
    uint8_t tipo;
    uint16_t li;         // indice nella pool delle liste (se TV_LISTA)
    double num;
    char testo[FAV_TESTO_MAX];

    static Val nulo() { Val x; memset(&x, 0, sizeof(x)); x.tipo = TV_NULO; return x; }
    static Val numero(double v) { Val x; memset(&x, 0, sizeof(x)); x.tipo = TV_NUM; x.num = v; return x; }
    static Val vero()  { return numero(1); }
    static Val uno()   { return numero(0); }
    static Val zero()  { return numero(0); }
    static Val stringa(const char* s) {
        Val x; memset(&x, 0, sizeof(x)); x.tipo = TV_TESTO;
        strncpy(x.testo, s, FAV_TESTO_MAX - 1); x.testo[FAV_TESTO_MAX - 1] = 0;
        return x;
    }
    static Val stringa_lunghezza(const char* s, uint16_t n) {
        Val x; memset(&x, 0, sizeof(x)); x.tipo = TV_TESTO;
        if (n > FAV_TESTO_MAX - 1) n = FAV_TESTO_MAX - 1;
        memcpy(x.testo, s, n); x.testo[n] = 0;
        return x;
    }
    bool e_numero() const { return tipo == TV_NUM; }
    bool e_testo()  const { return tipo == TV_TESTO; }
    bool e_vero()   const { return tipo == TV_NUM && num != 0; }
};

// ---------------------------------------------------------------
// Syscall: la scheda registra funzioni  Val (*)(int nargs, const Val* args)
// ---------------------------------------------------------------
typedef Val (*SyscallFn)(int nargs, const Val* args);

struct Syscall {
    const char* nome;
    SyscallFn fn;
    Syscall() : nome(0), fn(0) {}
    Syscall(const char* n, SyscallFn f) : nome(n), fn(f) {}
};

// ---------------------------------------------------------------
// La VM
// ---------------------------------------------------------------
class FavVM {
public:
    bool ok;
    char errore[160];

    FavVM() : ok(true), n_costanti(0), n_funzioni(0), n_globali(0),
              n_syscall(0), sp(0), n_frames(0), halt(false), contatore(0) {
        memset(errore, 0, sizeof(errore));
        for (int i = 0; i < FAV_LISTE_MAX; i++) { pool[i].vivo = false; pool[i].dict = false; pool[i].n = 0; }
    }

    void registra(const char* nome, SyscallFn fn) {
        if (n_syscall < FAV_SYSCALLS_MAX)
            syscalls[n_syscall++] = Syscall(nome, fn);
    }

    bool carica(const uint8_t* dati, size_t n) {
        if (n < 6 || memcmp(dati, "FVB1", 4) != 0)
            return fallito("bytecode non valido (manca FVB1)");
        size_t p = 6;
        uint16_t ncost = leggi_u16(dati, n, p);
        if (ncost > FAV_MAX_COSTANTI) return fallito("troppe costanti");
        for (uint16_t i = 0; i < ncost; i++) {
            if (p >= n) return fallito("costanti troncate");
            uint8_t t = dati[p++];
            if (t == 1) {
                if (p + 8 > n) return fallito("numero troncato");
                double v; memcpy(&v, dati + p, 8); p += 8;
                costanti[n_costanti++] = Val::numero(v);
            } else {
                uint16_t nl = leggi_u16(dati, n, p);
                if (p + nl > n) return fallito("testo troncato");
                costanti[n_costanti++] = Val::stringa_lunghezza((const char*)dati + p, nl);
                p += nl;
            }
        }
        uint16_t nfun = leggi_u16(dati, n, p);
        if (nfun > FAV_MAX_FUNZIONI) return fallito("troppe funzioni");
        for (uint16_t i = 0; i < nfun; i++) {
            uint16_t nk = leggi_u16(dati, n, p);
            uint8_t npar = dati[p++];
            uint8_t nloc = dati[p++];
            uint16_t ncode = leggi_u16(dati, n, p);
            if (p + ncode > n) return fallito("codice troncato");
            Funzione &f = funzioni[n_funzioni++];
            f.param = npar; f.nlocali = nloc;
            f.codice = dati + p; f.lunghezza = ncode;
            f.nome = costanti[nk].testo;
            p += ncode;
        }
        return true;
    }

    void avvia() {
        sp = 0; n_frames = 0; halt = false;
        for (int i = 0; i < FAV_LISTE_MAX; i++) pool[i].vivo = false;
        Frame &f = frames[n_frames++];
        f.fidx = 0; f.pc = 0; f.base_locali = 0;
    }

    // Esegue fino a n istruzioni. Ritorna false se il programma e' finito.
    bool esegui_istanti(uint32_t n) {
        if (halt || n_frames == 0) return false;
        uint32_t fine = contatore + n;
        while (contatore < fine) {
            if (!passo()) {
                halt = true;
                if (ok) { keep_finire = true; }
                return false;
            }
        }
        return true;
    }

    bool finito() const { return halt; }

    // ---- interfaccia per gli host (wrapper Swift / iOS) ----
    // Quante celle ha la lista li (-1 se la lista non e' viva).
    int lista_n(uint16_t li) const {
        if (li >= FAV_LISTE_MAX || !pool[li].vivo) return -1;
        return (int)pool[li].n;
    }
    // Elemento i della lista li (nulo se fuori gamma').
    const Val& lista_elem(uint16_t li, int i) const {
        static const Val vuoto = Val::nulo();
        if (li >= FAV_LISTE_MAX || !pool[li].vivo ||
            i < 0 || i >= (int)pool[li].n) return vuoto;
        return pool[li].items[i];
    }
    // Crea una lista: la usano le syscalls che ritornano liste
    // (os_tocco, os_file_lista, testo_dividi) esattamente come la VM Python.
    Val nuova_lista(int n, const Val* items) {
        if (n < 0) n = 0;
        if (n > FAV_LISTA_MAX) n = FAV_LISTA_MAX;
        int16_t li = alloca_lista(false);
        if (li < 0) return Val::nulo();
        for (int i = 0; i < n; i++) pool[li].items[i] = items[i];
        pool[li].n = (uint16_t)n;
        Val v = Val::nulo(); v.tipo = TV_LISTA; v.li = (uint16_t)li;
        return v;
    }

private:
    struct Funzione {
        const char* nome;
        uint8_t param;
        uint8_t nlocali;
        const uint8_t* codice;
        uint16_t lunghezza;
    };
    struct Frame {
        uint8_t fidx;
        uint16_t pc;
        uint8_t base_locali;   // dove iniziano argomenti+locali nello stack
    };
    struct Lista {
        bool vivo;
        bool segna;
        bool dict;                        // true = dizionario (coppie k,v)
        uint16_t n;
        Val items[FAV_LISTA_MAX];
    };

    Val costanti[FAV_MAX_COSTANTI];
    Funzione funzioni[FAV_MAX_FUNZIONI];
    Val globali[FAV_MAX_GLOBALI];
    const char* nomi_globali[FAV_MAX_GLOBALI];
    Val stiva[FAV_STIVA_MAX];
    Frame frames[FAV_FRAMES_MAX];
    Syscall syscalls[FAV_SYSCALLS_MAX];
    Lista pool[FAV_LISTE_MAX];
    bool keep_finire;

    uint16_t n_costanti;
    uint8_t n_funzioni;
    uint8_t n_globali;
    uint8_t n_syscall;
    uint8_t sp;
    uint8_t n_frames;
    bool halt;
    uint32_t contatore;

    uint16_t leggi_u16(const uint8_t* d, size_t n, size_t &p) {
        uint16_t v = (uint16_t)d[p] | ((uint16_t)d[p + 1] << 8);
        p += 2;
        return v;
    }

    bool fallito(const char* m) { strncpy(errore, m, sizeof(errore) - 1); ok = false; return false; }

    bool errore_run(const char* m) {
        snprintf(errore, sizeof(errore), "%s", m);
        ok = false;
        return false;
    }

    SyscallFn trova_syscall(const char* nome) {
        for (uint8_t i = 0; i < n_syscall; i++)
            if (strcmp(syscalls[i].nome, nome) == 0) return syscalls[i].fn;
        return 0;
    }

    // ---- gestione globali ----
    Val* trova_globale(const char* nome, bool crea) {
        for (uint8_t i = 0; i < n_globali; i++)
            if (strcmp(nomi_globali[i], nome) == 0) return &globali[i];
        if (crea && n_globali < FAV_MAX_GLOBALI) {
            nomi_globali[n_globali] = nome;    // punta nella tabella costanti
            globali[n_globali] = Val::nulo();
            return &globali[n_globali++];
        }
        return 0;
    }

    // ---- pool di liste ----
    int16_t alloca_lista(bool dict) {
        for (int16_t i = 0; i < FAV_LISTE_MAX; i++)
            if (!pool[i].vivo) {
                pool[i].vivo = true; pool[i].dict = dict; pool[i].n = 0;
                return i;
            }
        // pool pieno: prova il garbage collector e riprova
        if (raccogli_rifiuti() > 0) {
            for (int16_t i = 0; i < FAV_LISTE_MAX; i++)
                if (!pool[i].vivo) {
                    pool[i].vivo = true; pool[i].dict = dict; pool[i].n = 0;
                    return i;
                }
        }
        snprintf(errore, sizeof(errore), "troppe liste vive (max %d)", FAV_LISTE_MAX);
        ok = false;
        return -1;
    }

    uint16_t raccogli_rifiuti() {
        // segna
        for (int16_t i = 0; i < FAV_LISTE_MAX; i++) if (pool[i].vivo) pool[i].segna = false;
        // radici: stack e globali
        for (uint8_t i = 0; i < sp; i++) se_lista_segnala(stiva[i]);
        for (uint8_t i = 0; i < n_globali; i++) se_lista_segnala(globali[i]);
        // marca ricorsivamente (basta una passata serena, liste piatte)
        bool cambio = true;
        while (cambio) {
            cambio = false;
            for (int16_t i = 0; i < FAV_LISTE_MAX; i++) {
                if (!pool[i].vivo || pool[i].segna) continue;
                for (uint16_t j = 0; j < pool[i].n; j++)
                    if (pool[i].items[j].tipo == TV_LISTA &&
                        pool[pool[i].items[j].li].vivo &&
                        !pool[pool[i].items[j].li].segna) {
                        pool[i].segna = true;
                        cambio = true;
                        break;
                    }
            }
        }
        // spazza
        uint16_t liberate = 0;
        for (int16_t i = 0; i < FAV_LISTE_MAX; i++)
            if (pool[i].vivo && !pool[i].segna) { pool[i].vivo = false; liberate++; }
        return liberate;
    }

    void se_lista_segnala(Val &v) {
        if (v.tipo == TV_LISTA && v.li < FAV_LISTE_MAX && pool[v.li].vivo)
            pool[v.li].segna = true;
    }

    // ---- un'istruzione ----
    bool passo() {
        if (n_frames == 0) return false;
        Frame &fr = frames[n_frames - 1];
        const Funzione &f = funzioni[fr.fidx];
        const uint8_t* c = f.codice;
        if (fr.pc >= f.lunghezza) return ritorna(Val::nulo());
        uint8_t op = c[fr.pc];
        contatore++;

        switch (op) {
        case 1: {  // CONST
            uint16_t k = (uint16_t)c[fr.pc + 1] | ((uint16_t)c[fr.pc + 2] << 8);
            if (!push(costanti[k])) return false;
            fr.pc += 3; return true;
        }
        case 2: if (!push(Val::nulo())) return false;  fr.pc += 1; return true;
        case 3: if (!push(Val::vero()))  return false; fr.pc += 1; return true;
        case 4: if (!push(Val::zero())) return false; fr.pc += 1; return true;
        case 5: case 6: case 7: case 8: case 9: {   // ADD SUB MUL DIV MOD
            Val b = pop(), a = pop();
            Val r = aritmetica((int)op - 5, a, b);
            if (!ok) return false;
            if (!push(r)) return false;
            fr.pc += 1; return true;
        }
        case 10: {
            Val b = pop(), a = pop();
            if (!push(uguale(a, b) ? Val::vero() : Val::zero())) return false;
            fr.pc += 1; return true;
        }
        case 11: {
            Val b = pop(), a = pop();
            if (!push(!uguale(a, b) ? Val::vero() : Val::zero())) return false;
            fr.pc += 1; return true;
        }
        case 12: case 13: case 14: case 15: {
            Val b = pop(), a = pop();
            int cc = confronto(a, b);
            if (op == 12 && !push(cc <  0 ? Val::vero() : Val::zero())) return false;
            if (op == 13 && !push(cc >  0 ? Val::vero() : Val::zero())) return false;
            if (op == 14 && !push(cc <= 0 ? Val::vero() : Val::zero())) return false;
            if (op == 15 && !push(cc >= 0 ? Val::vero() : Val::zero())) return false;
            fr.pc += 1; return true;
        }
        case 16: {
            Val b = pop(), a = pop();
            if (!push((a.e_vero() && b.e_vero()) ? Val::vero() : Val::zero())) return false;
            fr.pc += 1; return true;
        }
        case 17: {
            Val b = pop(), a = pop();
            if (!push((a.e_vero() || b.e_vero()) ? Val::vero() : Val::zero())) return false;
            fr.pc += 1; return true;
        }
        case 18: {
            Val a = pop();
            if (!push(a.e_vero() ? Val::zero() : Val::vero())) return false;
            fr.pc += 1; return true;
        }
        case 19: {
            Val a = pop();
            if (!a.e_numero()) return errore_run("meno singolo non numerico");
            if (!push(Val::numero(-a.num))) return false;
            fr.pc += 1; return true;
        }
        case 33: pop(); fr.pc += 1; return true;   // POP
        case 0:  fr.pc += 1; return true;          // NOP

        case 20: case 21: {  // GETG / SETG
            uint16_t k = (uint16_t)c[fr.pc + 1] | ((uint16_t)c[fr.pc + 2] << 8);
            const char* nome = costanti[k].testo;
            Val* g = trova_globale(nome, op == 21);
            if (!g) return errore_run("variabile non trovata o globali piene");
            if (op == 20) { if (!push(*g)) return false; }
            else *g = pop();
            fr.pc += 3; return true;
        }
        case 22: {
            uint8_t idx = c[fr.pc + 1];
            if (!push(stiva[fr.base_locali + idx])) return false;
            fr.pc += 2; return true;
        }
        case 23: {
            uint8_t idx = c[fr.pc + 1];
            stiva[fr.base_locali + idx] = pop();
            fr.pc += 2; return true;
        }

        // ----- LIST / DICT -----
        case 26: {
            uint8_t n = c[fr.pc + 1];
            int16_t li = alloca_lista(false);
            if (li < 0) return false;
            for (int i = 0; i < n; i++)
                pool[li].items[i] = stiva[sp - n + i];
            pool[li].n = n;
            sp -= n;
            Val v = Val::nulo(); v.tipo = TV_LISTA; v.li = (uint16_t)li;
            if (!push(v)) return false;
            fr.pc += 2; return true;
        }
        case 27: {
            uint8_t np = c[fr.pc + 1];
            int16_t li = alloca_lista(true);
            if (li < 0) return false;
            pool[li].n = np * 2;
            for (int i = 0; i < np * 2; i++)
                pool[li].items[i] = stiva[sp - np * 2 + i];
            sp -= np * 2;
            Val v = Val::nulo(); v.tipo = TV_LISTA; v.li = (uint16_t)li;
            if (!push(v)) return false;
            fr.pc += 2; return true;
        }
        case 24: {  // GETI lista[i] / dict["chiave"]
            Val idx = pop(), obj = pop();
            if (obj.tipo != TV_LISTA) return errore_run("questo valore non si indicizza");
            Lista &L = pool[obj.li];
            if (L.dict) {
                if (!idx.e_testo()) return errore_run("le chiavi del dizionario sono testo");
                for (uint16_t i = 0; i + 1 < L.n; i += 2)
                    if (L.items[i].e_testo() && strcmp(L.items[i].testo, idx.testo) == 0) {
                        if (!push(L.items[i + 1])) return false;
                        fr.pc += 1; return true;
                    }
                return errore_run("chiave non trovata nel dizionario");
            } else {
                if (!idx.e_numero()) return errore_run("l'indice della lista e' un numero");
                int i = (int)idx.num;
                if (i < 0 || i >= (int)L.n) return errore_run("indice fuori dalla lista");
                if (!push(L.items[i])) return false;
                fr.pc += 1; return true;
            }
        }
        case 25: {  // SETI val
            Val valore = pop(), idx = pop(), obj = pop();
            if (obj.tipo != TV_LISTA) return errore_run("questo valore non si indicizza");
            Lista &L = pool[obj.li];
            int i;
            if (L.dict) {
                if (!idx.e_testo()) return errore_run("le chiavi del dizionario sono testo");
                for (i = 0; i + 1 < (int)L.n; i += 2)
                    if (L.items[i].e_testo() && strcmp(L.items[i].testo, idx.testo) == 0) break;
                if (i + 1 >= (int)L.n && L.n + 2 > FAV_LISTA_MAX)
                    return errore_run("dizionario pieno");
                if (i + 1 >= (int)L.n) {
                    L.items[L.n++] = idx;
                    L.items[L.n++] = valore;
                } else L.items[i + 1] = valore;
            } else {
                if (!idx.e_numero()) return errore_run("l'indice della lista e' un numero");
                i = (int)idx.num;
                if (i < 0 || i >= (int)L.n) return errore_run("indice fuori dalla lista");
                L.items[i] = valore;
            }
            fr.pc += 1; return true;
        }

        case 28: {  // CALLN (syscall)
            uint16_t k = (uint16_t)c[fr.pc + 1] | ((uint16_t)c[fr.pc + 2] << 8);
            uint8_t nargs = c[fr.pc + 3];
            const char* nome = costanti[k].testo;
            // funzioni liste gestite dentro la VM (toccano la pool privata)
            Val r;
            if (lista_builtin(nome, nargs, r)) {
                if (!ok) return false;
                if (!push(r)) return false;
                fr.pc += 4; return true;
            }
            SyscallFn fn = trova_syscall(nome);
            if (!fn) return errore_run("syscall sconosciuta");
            Val args[8];
            if (nargs > 8) return errore_run("troppi argomenti");
            for (int i = 0; i < nargs; i++) args[i] = stiva[sp - nargs + i];
            sp -= nargs;
            r = fn(nargs, args);
            if (!push(r)) return false;
            fr.pc += 4; return true;
        }
        case 29: {  // CALLF
            uint8_t fidx = c[fr.pc + 1];
            uint8_t nargs = c[fr.pc + 2];
            if (fidx >= n_funzioni) return errore_run("funzione inesistente");
            const Funzione &g = funzioni[fidx];
            if (nargs != g.param) return errore_run("numero argomenti sbagliato");
            frames[n_frames - 1].pc = fr.pc + 3;
            if (n_frames >= FAV_FRAMES_MAX) return errore_run("troppa ricorsione");
            uint8_t base = sp - nargs;
            for (int i = nargs; i < g.nlocali; i++) stiva[sp++] = Val::nulo();
            Frame &nf = frames[n_frames++];
            nf.fidx = fidx; nf.pc = 0; nf.base_locali = base;
            return true;
        }
        case 35: {  // FORT
            if (sp < 3) return errore_run("ciclo per: stack insufficiente");
            Val cont = pop();
            Val passo = stiva[sp - 1];
            Val fine = stiva[sp - 2];
            if (!passo.e_numero() || !fine.e_numero() || !cont.e_numero())
                return errore_run("ciclo per con valori non numerici");
            bool continua = (passo.num > 0) ? (cont.num <= fine.num)
                                            : (cont.num >= fine.num);
            if (!push(continua ? Val::vero() : Val::zero())) return false;
            fr.pc += 1; return true;
        }
        case 30:
            fr.pc = (uint16_t)c[fr.pc + 1] | ((uint16_t)c[fr.pc + 2] << 8);
            return true;
        case 31: {
            uint16_t a = (uint16_t)c[fr.pc + 1] | ((uint16_t)c[fr.pc + 2] << 8);
            Val v = pop();
            if (!v.e_vero()) fr.pc = a; else fr.pc += 3;
            return true;
        }
        case 32: { Val r = pop(); return ritorna(r); }
        case 34: return false;   // HALT
        default:
            return errore_run("opcode sconosciuto");
        }
    }

    // builtin per le liste: lista_lunghezza, lista_aggiungi_inizio,
    // lista_togli_ultimo, lista_togli_primo, lista_aggiungi
    bool lista_builtin(const char* nome, int nargs, Val &risposta) {
        if (nargs < 1) return false;
        Val l = stiva[sp - nargs];
        if (l.tipo != TV_LISTA) {
            if (strcmp(nome, "lista_lunghezza") == 0) {
                if (nargs == 0) return false;
                risposta = Val::numero(0);
                return true;
            }
            return false;
        }
        if (strcmp(nome, "lista_lunghezza") == 0) {
            sp -= nargs;
            risposta = Val::numero(pool[l.li].n);
            return true;
        }
        if (strcmp(nome, "lista_aggiungi_inizio") == 0 && nargs == 2) {
            Lista &L = pool[l.li];
            if (L.n >= FAV_LISTA_MAX) { errore_run("lista piena"); return true; }
            for (uint16_t i = L.n; i > 0; i--) L.items[i] = L.items[i - 1];
            L.items[0] = stiva[sp - 1];
            L.n++;
            sp -= 2;
            risposta = Val::nulo();
            return true;
        }
        if (strcmp(nome, "lista_aggiungi") == 0 && nargs == 2) {
            Lista &L = pool[l.li];
            if (L.n >= FAV_LISTA_MAX) { errore_run("lista piena"); return true; }
            L.items[L.n++] = stiva[sp - 1];
            sp -= 2;
            risposta = Val::nulo();
            return true;
        }
        if (strcmp(nome, "lista_togli_ultimo") == 0 && nargs == 1) {
            Lista &L = pool[l.li];
            if (L.n == 0) { errore_run("lista vuota"); ok = false; return true; }
            risposta = L.items[--L.n];
            sp -= 1;
            return true;
        }
        if (strcmp(nome, "lista_togli_primo") == 0 && nargs == 1) {
            Lista &L = pool[l.li];
            if (L.n == 0) { errore_run("lista vuota"); ok = false; return true; }
            risposta = L.items[0];
            for (uint16_t i = 0; i + 1 < L.n; i++) L.items[i] = L.items[i + 1];
            L.n--;
            sp -= 1;
            return true;
        }
        return false;
    }

    bool ritorna(Val r) {
        uint8_t base_morta = frames[n_frames - 1].base_locali;
        n_frames--;
        if (n_frames == 0) return false;   // main finito
        sp = base_morta;
        if (!push(r)) return false;
        return true;
    }

    bool push(const Val &v) {
        if (sp >= FAV_STIVA_MAX) { errore_run("stack pieno"); return false; }
        stiva[sp++] = v;
        return true;
    }
    Val pop() {
        if (sp == 0) { errore_run("stack vuoto"); ok = false; return Val::nulo(); }
        return stiva[--sp];
    }

    Val aritmetica(int op, const Val &a, const Val &b) {
        if (op == 0 && (a.e_testo() || b.e_testo())) {
            char buf[FAV_TESTO_MAX];
            snprintf(buf, sizeof(buf), "%s%s", in_testo(a), in_testo(b));
            return Val::stringa(buf);
        }
        if (!a.e_numero() || !b.e_numero()) {
            snprintf(errore, sizeof(errore), "operazione tra valori non numerici");
            ok = false;
            return Val::nulo();
        }
        switch (op) {
        case 0: return Val::numero(a.num + b.num);
        case 1: return Val::numero(a.num - b.num);
        case 2: return Val::numero(a.num * b.num);
        case 3:
            if (b.num == 0) { snprintf(errore, sizeof(errore), "divisione per zero"); ok = false; return Val::nulo(); }
            return Val::numero(a.num / b.num);
        case 4:
            if (b.num == 0) { snprintf(errore, sizeof(errore), "resto per zero"); ok = false; return Val::nulo(); }
            return Val::numero((double)((long)a.num % (long)b.num));
        }
        return Val::nulo();
    }

    bool uguale(const Val &a, const Val &b) {
        if (a.tipo != b.tipo) return false;
        if (a.tipo == TV_NUM) return a.num == b.num;
        if (a.tipo == TV_TESTO) return strcmp(a.testo, b.testo) == 0;
        return a.li == b.li;
    }

    int confronto(const Val &a, const Val &b) {
        if (a.e_testo() && b.e_testo()) return strcmp(a.testo, b.testo);
        double d = a.num - b.num;
        return d < 0 ? -1 : (d > 0 ? 1 : 0);
    }

    const char* in_testo(const Val &v) {
        if (v.e_testo()) return v.testo;
        static char buf[32];
        if (v.tipo == TV_NULO) { strcpy(buf, "niente"); return buf; }
        if (v.num == (long)v.num) snprintf(buf, sizeof(buf), "%ld", (long)v.num);
        else snprintf(buf, sizeof(buf), "%g", v.num);
        return buf;
    }
};

#endif  // FAVOS_VM_H
