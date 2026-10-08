// test_host.cpp — verifica locale del ponte C favos_host.
// Compila e gira la stessa strada che percorre la Swift:
//   crea -> contesto -> registra -> carica -> avvia -> esegui
//
// g++ -std=c++11 -ISources/CFavOSVM/include -o tests_cpp/test_host
//     tests_cpp/test_host.cpp Sources/CFavOSVM/favos_host.cpp

#include "favos_host.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string>
#include <vector>

static std::vector<std::string> output;
static std::string ultimo_errore;

static void val_testo(const FavVal& v, char* buf, size_t cap) {
    if (v.tipo == 2) { snprintf(buf, cap, "%s", v.testo); return; }
    if (v.tipo == 1) {
        if (v.num == (long)v.num) snprintf(buf, cap, "%ld", (long)v.num);
        else snprintf(buf, cap, "%g", v.num);
        return;
    }
    snprintf(buf, cap, "niente");
}

// La callback Swift (qui C): implementa le syscalls di test.
static void chiamata(void* utente, const char* nome, int32_t n,
                     const FavVal* arg, FavVal* risposta,
                     FavVal* pool, int32_t cap) {
    (void)utente; (void)pool; (void)cap;
    risposta->tipo = 0;

    if (strcmp(nome, "stampa") == 0 || strcmp(nome, "os_scrivi") == 0) {
        std::string riga;
        for (int32_t i = 0; i < n; i++) {
            char buf[FAV_VAL_TESTO];
            val_testo(arg[i], buf, sizeof(buf));
            if (i) riga += " ";
            riga += buf;
        }
        output.push_back(riga);
        return;
    }
    if (strcmp(nome, "num_testo") == 0 && n >= 1) {
        val_testo(arg[0], risposta->testo, FAV_VAL_TESTO);
        risposta->tipo = 2;
        return;
    }
    if (strcmp(nome, "testo_lunghezza") == 0 && n >= 1) {
        risposta->tipo = 1;
        risposta->num = (double)strlen(arg[0].testo);
        return;
    }
    if (strcmp(nome, "testo_maiuscolo") == 0 && n >= 1) {
        snprintf(risposta->testo, FAV_VAL_TESTO, "%s", arg[0].testo);
        for (char* p = risposta->testo; *p; p++)
            if (*p >= 'a' && *p <= 'z') *p -= 32;
        risposta->tipo = 2;
        return;
    }
    if (strcmp(nome, "os_tocco") == 0) {
        // ritorna la lista [10, 20] come farebbe il kernel con un tocco
        risposta->tipo = 3;
        risposta->elementi = pool;
        risposta->n_elementi = 2;
        pool[0].tipo = 1; pool[0].num = 10;
        pool[1].tipo = 1; pool[1].num = 20;
        return;
    }
    if (strcmp(nome, "testo_unisci") == 0 && n >= 2) {
        // arg[0] e' una lista di testi, arg[1] il separatore
        std::string s;
        if (arg[0].tipo == 3) {
            for (int32_t i = 0; i < arg[0].n_elementi; i++) {
                char buf[FAV_VAL_TESTO];
                val_testo(arg[0].elementi[i], buf, sizeof(buf));
                if (i) s += arg[1].testo;
                s += buf;
            }
        }
        snprintf(risposta->testo, FAV_VAL_TESTO, "%s", s.c_str());
        risposta->tipo = 2;
        return;
    }
    ultimo_errore = std::string("syscall non gestita in test: ") + nome;
}

static const char* NOMI[] = {
    "stampa", "os_scrivi", "num_testo", "testo_num", "testo_lunghezza",
    "testo_pezzo", "testo_trova", "testo_dividi", "testo_unisci",
    "testo_maiuscolo", "testo_minuscolo", "num_assoluto", "num_intero",
    "num_min", "num_max", "os_disegna_rett", "os_disegna_testo",
    "os_schermo_pulisci", "os_tasti_num", "os_leggi_tasto", "os_tempo_ms",
    "os_pausa", "os_random", "os_file_leggi", "os_file_scrivi",
    "os_file_cancella", "os_file_lista", "os_avvia", "os_titolo", "os_bip",
    "os_tocco", "os_web_cerca_google", "os_web_cerca_youtube",
    "os_web_apri", "os_web_stato"
};

static uint8_t* leggi_file(const char* path, size_t* n) {
    FILE* f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long lung = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t* buf = (uint8_t*)malloc(lung);
    if (fread(buf, 1, lung, f) != (size_t)lung) { fclose(f); free(buf); return NULL; }
    fclose(f);
    *n = (size_t)lung;
    return buf;
}

static int esegui_app(const char* path, int budget) {
    size_t n = 0;
    uint8_t* dati = leggi_file(path, &n);
    if (!dati) { printf("ERRORE: non trovo %s\n", path); return 1; }

    FavHost* h = favhost_crea();
    favhost_contesto(h, NULL, chiamata);
    for (size_t i = 0; i < sizeof(NOMI) / sizeof(NOMI[0]); i++)
        if (!favhost_registra(h, NOMI[i])) {
            printf("ERRORE: registra %s fallito\n", NOMI[i]);
            return 1;
        }
    if (!favhost_carica(h, dati, n)) {
        printf("ERRORE caricamento %s: %s\n", path, favhost_errore(h));
        return 1;
    }
    favhost_avvia(h);
    int giri = 0;
    while (favhost_esegui(h, 3000)) {
        if (++giri > budget) { printf("ERRORE: loop infinito\n"); return 1; }
    }
    if (!favhost_ok(h)) {
        printf("ERRORE VM (%s): %s\n", path, favhost_errore(h));
        return 1;
    }
    favhost_distruggi(h);
    free(dati);
    return 0;
}

static int confronta(const char* etichetta, const char* atteso) {
    std::string a;
    for (size_t i = 0; i < output.size(); i++) {
        a += output[i];
        a += "\n";
    }
    if (a != atteso) {
        printf("FALLITO %s\n--- atteso ---\n%s--- avuto ---\n%s---\n",
               etichetta, atteso, a.c_str());
        return 1;
    }
    printf("OK %s\n", etichetta);
    return 0;
}

int main(int argc, char** argv) {
    if (argc < 3) {
        printf("Uso: test_host cartella_app\n");
        return 2;
    }
    char percorso[512];
    int falliti = 0;

    // 1) app classica: stampa + num_testo
    snprintf(percorso, sizeof(percorso), "%s/ciao.fvb", argv[1]);
    output.clear();
    if (esegui_app(percorso, 200)) return 1;
    falliti += confronta("ciao.fvb",
        "=== App Ciao, in Favilla ===\n"
        "Ciao Davide!\n"
        "tra 14 anni sara' il 2050\n"
        "Oggi e' il 17 ottobre\n"
        "Prova di matematica: 7 * 6 = 42\n"
        "Ciao app finita. ESC per tornare alla shell.\n");

    // 2) liste: os_tocco ritorna lista, testo_unisci riceve lista
    if (argc > 2) {
        output.clear();
        if (esegui_app(argv[2], 200)) return 1;
        falliti += confronta("liste (os_tocco + testo_unisci)",
            "tocco 10,20\n"
            "lista: 2\n"
            "ciao-mondo\n"
            "fine\n");
    }

    if (!ultimo_errore.empty()) {
        printf("ERRORE callback: %s\n", ultimo_errore.c_str());
        return 1;
    }
    printf(falliti ? "FALLITI: %d\n" : "TUTTI I TEST OK (%d falliti)\n", falliti);
    return falliti ? 1 : 0;
}
