# WI-016 — esecutore minimo di UN worker del Company Brain (un contenitore, una credenziale, un agente).
# Predisposto e NON distribuito: nessun hosting è stato scelto. Il contenitore esegue un lotto e termina; la cadenza è
# dello schedulatore dell'ospite. Nessuna chiave amministrativa, nessuna chiamata AI, nessun file scritto.
#
#   docker build -f tools/company-brain/Dockerfile -t vinea-brain-worker .
#   docker run --rm --read-only -e VINEA_WORKER_ENABLED=true -e VINEA_AGENT_DATABASE_URL -e VINEA_DB_CA_PEM vinea-brain-worker
#
# Esecuzione AUTONOMA (ospite senza schedulatore proprio): stessa immagine, un lotto ogni N minuti; il processo esce con
# codice 1 dopo tre giri falliti di fila, cosi l'ospite lo riavvia e avvisa.
#   docker run -d --restart on-failure --read-only -e VINEA_WORKER_ENABLED=true -e VINEA_AGENT_DATABASE_URL \n#     -e VINEA_DB_CA_PEM -e VINEA_WORKER_INTERVAL_MINUTES=15 \n#     --entrypoint bun vinea-brain-worker tools/company-brain/esecutore.mjs
FROM oven/bun:1.3.14-alpine
WORKDIR /app
COPY tools/company-brain/worker.mjs tools/company-brain/esecutore.mjs tools/company-brain/segnale.mjs tools/company-brain/osservatore.mjs tools/company-brain/
COPY tools/company-brain/lib tools/company-brain/lib
COPY tools/wine-catalog/lib/cloud-tls.mjs tools/wine-catalog/lib/
USER bun
ENTRYPOINT ["bun", "tools/company-brain/worker.mjs"]
CMD ["--max", "5"]
