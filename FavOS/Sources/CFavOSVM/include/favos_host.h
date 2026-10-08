// favos_host.h — API C della VM Favilla per l'host Swift di favOS.
//
// Solo C: Swift importa questo header senza interop C++; la VM C++
// (favos_vm.h) resta nascosta dentro favos_host.cpp.
//
// Ciclo di vita tipico:
//     FavHost* h = favhost_crea();
//     favhost_contesto(h, utente, chiamata);
//     favhost_registra(h, "stampa");  ... (tutte le syscalls)
//     favhost_carica(h, bytecode, n); // il buffer e' copiato dall'host
//     favhost_avvia(h);
//     while (favhost_esegui(h, 3000)) { ... }
//
// Le syscalls arrivano in `chiamata`: la Swift scrive la risposta nel
// puntatore `risposta`. Per ritornare una lista usa `pool` (memoria
// dell'host, valida solo durante la chiamata).

#ifndef FAVOS_HOST_H
#define FAVOS_HOST_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define FAV_VAL_TESTO 64     // lunghezza massima stringa (= FAV_TESTO_MAX)

typedef struct FavHost FavHost;

// Valore che passa fra Swift e VM.
// tipo: 0 = niente, 1 = numero, 2 = testo, 3 = lista
typedef struct FavVal {
    int32_t tipo;
    double  num;
    char    testo[FAV_VAL_TESTO];
    struct FavVal* elementi;   // solo per tipo 3
    int32_t n_elementi;
} FavVal;

// Callback per le syscalls. `pool` e' il buffer (cap celle) in cui
// scrivere gli elementi di una lista di risposta: resta valido solo
// per la durata della chiamata.
typedef void (*FavChiamata)(void* utente, const char* nome,
                            int32_t n, const FavVal* arg,
                            FavVal* risposta,
                            FavVal* pool, int32_t cap);

FavHost*  favhost_crea(void);
void      favhost_distruggi(FavHost* h);
void      favhost_contesto(FavHost* h, void* utente, FavChiamata cb);
int32_t   favhost_registra(FavHost* h, const char* nome);
int32_t   favhost_carica(FavHost* h, const uint8_t* dati, size_t n);
void      favhost_avvia(FavHost* h);
int32_t   favhost_esegui(FavHost* h, uint32_t istruzioni);  // 1 = ancora vivo
int32_t   favhost_ok(FavHost* h);
int32_t   favhost_finito(FavHost* h);
const char* favhost_errore(FavHost* h);

#ifdef __cplusplus
}
#endif
#endif  // FAVOS_HOST_H
