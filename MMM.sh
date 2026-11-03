
#!/bin/bash

# ==========================================
# SCARICATORE YOUTUBE - DEBIAN
# ==========================================

DESTINO="$HOME"
FORMATO="mp3"

# ==========================================
# FUNZIONE: CONTROLLO VERSIONE E INSTALLAZIONE
# ==========================================

check_ver() {

    echo
    echo "========== CONTROLLO YT-DLP =========="

    if ! command -v curl >/dev/null 2>&1; then
        echo "Installazione di curl..."
        sudo apt update
        sudo apt install -y curl
    fi

    VERSIONE_INSTALLATA=""

    if command -v yt-dlp >/dev/null 2>&1; then
        VERSIONE_INSTALLATA=$(yt-dlp --version 2>/dev/null)
    fi

    VERSIONE_ULTIMA=$(curl -fsSL \
        https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest \
        | grep '"tag_name"' \
        | head -n 1 \
        | cut -d '"' -f 4)

    if [[ -z "$VERSIONE_ULTIMA" ]]; then
        echo "Impossibile verificare la versione online."
        return 1
    fi

    echo "Versione installata: ${VERSIONE_INSTALLATA:-Non installato}"
    echo "Ultima versione:     $VERSIONE_ULTIMA"

    if [[ "$VERSIONE_INSTALLATA" != "$VERSIONE_ULTIMA" ]]; then

        echo
        read -r -p "Installare/aggiornare yt-dlp? (s/n): " RISPOSTA

        if [[ "$RISPOSTA" =~ ^[Ss]$ ]]; then

            sudo apt update
            sudo apt install -y ffmpeg

            sudo curl -fL \
                https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
                -o /usr/local/bin/yt-dlp

            sudo chmod a+rx /usr/local/bin/yt-dlp

            if ! yt-dlp --version >/dev/null 2>&1; then
                echo "Errore durante l'installazione."
                return 1
            fi

            echo "Installazione completata."

        else
            echo "Installazione annullata."
            return 1
        fi

    else
        echo "yt-dlp è già aggiornato."
    fi

    if ! command -v ffmpeg >/dev/null 2>&1; then
        echo
        echo "FFmpeg non è installato."
        read -r -p "Installarlo adesso? (s/n): " RISPOSTA

        if [[ "$RISPOSTA" =~ ^[Ss]$ ]]; then
            sudo apt install -y ffmpeg
        else
            echo "Attenzione: alcune conversioni potrebbero non funzionare."
        fi
    fi

    echo
    return 0
}

# ==========================================
# FUNZIONE: SCELTA DIRECTORY
# ==========================================

scegli_directory() {

    echo
    echo "Directory attuale: $DESTINO"
    read -r -p "Inserisci la nuova directory (Invio per mantenere quella attuale): " NUOVA_DIR

    if [[ -n "$NUOVA_DIR" ]]; then

        NUOVA_DIR="${NUOVA_DIR/#\~/$HOME}"

        mkdir -p "$NUOVA_DIR"

        if [[ -d "$NUOVA_DIR" && -w "$NUOVA_DIR" ]]; then
            DESTINO="$NUOVA_DIR"
            echo "Directory impostata: $DESTINO"
        else
            echo "Directory non valida o non scrivibile."
        fi
    fi
}

# ==========================================
# FUNZIONE: SCELTA FORMATO
# ==========================================

scegli_formato() {

    echo
    echo "========== FORMATO DOWNLOAD =========="
    echo "1) MP3 - Solo audio"
    echo "2) MP4 - Video"
    echo

    read -r -p "Seleziona formato: " SCELTA

    case "$SCELTA" in
        1) FORMATO="mp3" ;;
        2) FORMATO="mp4" ;;
        *) echo "Scelta non valida." ;;
    esac

    echo "Formato attivo: ${FORMATO^^}"
}

# ==========================================
# FUNZIONE: DOWNLOAD PLAYLIST
# ==========================================

scarica_playlist() {

    echo
    read -r -p "Incolla il link della playlist: " URL

    [[ -z "$URL" ]] && return

    echo
    echo "Recupero nome playlist..."

    ALBUM=$(yt-dlp --flat-playlist --print "%(playlist_title)s" "$URL" 2>/dev/null | head -n 1)

    if [[ -z "$ALBUM" ]]; then
        echo "Impossibile recuperare il nome della playlist."
        return
    fi

    # Pulisce il nome della cartella
    ALBUM=$(printf '%s' "$ALBUM" | tr '/:' '__')

    CARTELLA="$DESTINO/$ALBUM"

    mkdir -p "$CARTELLA"

    echo
    echo "Album: $ALBUM"
    echo "Destinazione: $CARTELLA"
    echo "Formato: ${FORMATO^^}"
    echo
    read -r -p "Eseguire in background? (s/n): " BG

    if [[ "$BG" =~ ^[Ss]$ ]]; then
        avvia_background "playlist" "$URL" "$CARTELLA" "$FORMATO"
    else
        if [[ "$FORMATO" == "mp3" ]]; then
            yt-dlp --yes-playlist -x \
                --audio-format mp3 --audio-quality 0 \
                --embed-metadata \
                -o "$CARTELLA/%(playlist_index)02d - %(title)s.%(ext)s" "$URL"
        else
            yt-dlp --yes-playlist -f "bv*+ba/b" \
                --merge-output-format mp4 \
                -o "$CARTELLA/%(playlist_index)02d - %(title)s.%(ext)s" "$URL"
        fi
    fi
    echo
}

# ==========================================
# FUNZIONE: DOWNLOAD SINGOLO BRANO
# ==========================================

scarica_singolo() {

    echo
    read -r -p "Incolla il link del video: " URL

    [[ -z "$URL" ]] && return

          read -r -p "Eseguire in background? (s/n): " BG

    if [[ "$BG" =~ ^[Ss]$ ]]; then
        avvia_background "singolo" "$URL" "$DESTINO" "$FORMATO"
    else
        if [[ "$FORMATO" == "mp3" ]]; then
            yt-dlp --no-playlist -x \
                --audio-format mp3 --audio-quality 0 \
                --embed-metadata \
                -o "$DESTINO/%(title)s.%(ext)s" "$URL"
        else
            yt-dlp --no-playlist -f "bv*+ba/b" \
                --merge-output-format mp4 \
                -o "$DESTINO/%(title)s.%(ext)s" "$URL"
        fi
    fi
    echo
}

# ==========================================
# CONTROLLO INIZIALE
# ==========================================

clear

echo "======================================"
echo "       SCARICATORE YOUTUBE"
echo "======================================"

if ! check_ver; then
    echo "Impossibile proseguire senza yt-dlp aggiornato."
    exit 1
fi

scegli_directory


# ==========================================
# BACKGROUND DOWNLOAD MANAGER
# ==========================================

LOG_DIR="$HOME/.youtube_downloader/logs"
mkdir -p "$LOG_DIR"

avvia_background() {

    local TIPO="$1"
    local URL="$2"
    local CARTELLA="$3"
    local FORMATO_JOB="$4"

    local TIMESTAMP
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)

    local LOG="$LOG_DIR/download_${TIMESTAMP}.log"

    if [[ "$TIPO" == "playlist" ]]; then

        if [[ "$FORMATO_JOB" == "mp3" ]]; then

            nohup yt-dlp \
                --yes-playlist \
                -x \
                --audio-format mp3 \
                --audio-quality 0 \
                --embed-metadata \
                -o "$CARTELLA/%(playlist_index)02d - %(title)s.%(ext)s" \
                "$URL" > "$LOG" 2>&1 </dev/null &

        else

            nohup yt-dlp \
                --yes-playlist \
                -f "bv*+ba/b" \
                --merge-output-format mp4 \
                -o "$CARTELLA/%(playlist_index)02d - %(title)s.%(ext)s" \
                "$URL" > "$LOG" 2>&1 </dev/null &

        fi

    else

        if [[ "$FORMATO_JOB" == "mp3" ]]; then

            nohup yt-dlp \
                --no-playlist \
                -x \
                --audio-format mp3 \
                --audio-quality 0 \
                --embed-metadata \
                -o "$CARTELLA/%(title)s.%(ext)s" \
                "$URL" > "$LOG" 2>&1 </dev/null &

        else

            nohup yt-dlp \
                --no-playlist \
                -f "bv*+ba/b" \
                --merge-output-format mp4 \
                -o "$CARTELLA/%(title)s.%(ext)s" \
                "$URL" > "$LOG" 2>&1 </dev/null &

        fi

    fi

    local PID=$!

    echo "$PID|$TIPO|$FORMATO_JOB|$LOG" >> "$LOG_DIR/processes.txt"

    echo
    echo "Download avviato in background."
    echo "PID: $PID"
    echo "Log: $LOG"
}

# ==========================================
# BACKGROUND PROCESS LIST
# ==========================================

mostra_processi() {

    echo
    echo "========== DOWNLOAD IN BACKGROUND =========="

    if [[ ! -f "$LOG_DIR/processes.txt" ]]; then
        echo "Nessun processo registrato."
        return
    fi

    while IFS='|' read -r PID TIPO FORMATO_JOB LOG; do

        if kill -0 "$PID" 2>/dev/null; then
            echo "PID: $PID | $TIPO | ${FORMATO_JOB^^} | ATTIVO"
        else
            echo "PID: $PID | $TIPO | ${FORMATO_JOB^^} | TERMINATO"
        fi

        echo "Log: $LOG"
        echo

    done < "$LOG_DIR/processes.txt"
}

# ==========================================
# VIEW DOWNLOAD LOG
# ==========================================

visualizza_log() {

    echo
    read -r -p "Inserisci il PID del download: " PID

    local LOG
    LOG=$(awk -F'|' -v pid="$PID" '$1 == pid {print $4}' "$LOG_DIR/processes.txt" 2>/dev/null)

    if [[ -n "$LOG" && -f "$LOG" ]]; then
        tail -n 40 "$LOG"
    else
        echo "Log non trovato."
    fi
}

# ==========================================
# MENU PRINCIPALE
# ==========================================

while true; do

    clear

    echo "======================================"
    echo "       SCARICATORE YOUTUBE"
    echo "======================================"
    echo
    echo "Directory : $DESTINO"
    echo "Formato   : ${FORMATO^^}"
    echo
    echo "--------------------------------------"
    echo "1) Installa o Controlla/Aggiorna yt-dlp"
    echo "2) Cambia directory"
    echo "3) Cambia formato MP3/MP4"
    echo "4) Scarica playlist"
    echo "5) Scarica singolo brano"
    echo "6) Visualizza download in background"
    echo "7) Visualizza log di un download"
    echo "0) Esci"
    echo "--------------------------------------"
    echo

    read -r -p "Seleziona un'opzione: " SCELTA

    case "$SCELTA" in

        1)
            check_ver
            read -r -p "Premi INVIO per continuare..."
            ;;

        2)
            scegli_directory
            read -r -p "Premi INVIO per continuare..."
            ;;

        3)
            scegli_formato
            read -r -p "Premi INVIO per continuare..."
            ;;

        4)
            scarica_playlist
            read -r -p "Premi INVIO per tornare al menu..."
            ;;

        5)
            scarica_singolo
            read -r -p "Premi INVIO per tornare al menu..."
            ;;
	6)
    	    mostra_processi
    	    read -r -p "Premi INVIO per continuare..."
    	    ;;

	7)
    	    visualizza_log
	    read -r -p "Premi INVIO per continuare..."
    	    ;;

        0)
            echo
            echo "Chiusura programma."
            exit 0
            ;;

        *)
            echo "Scelta non valida."
            sleep 1
            ;;

    esac

done

