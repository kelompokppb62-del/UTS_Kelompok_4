FROM eclipse-temurin:21-jre-noble AS java
FROM node:22-trixie-slim

COPY --from=java /opt/java/openjdk /opt/java/openjdk
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH="/opt/java/openjdk/bin:${PATH}" CI=true FIREBASE_CLI_DISABLE_UPDATE_CHECK=1

RUN java -version \
    && npm install --global --no-audit --no-fund firebase-tools@15.36.0 \
    && npm cache clean --force \
    && install -d -o node -g node -m 0750 /data /workspace \
    && install -o node -g node -m 0640 /dev/null /data/.keep

WORKDIR /workspace
USER node
RUN firebase setup:emulators:firestore && firebase setup:emulators:ui

COPY firebase.emulator.json ./
COPY database/firestore.rules database/firestore.indexes.json ./database/

CMD ["sh", "-ec", "if [ -f /data/export/firebase-export-metadata.json ]; then set -- --import=/data/export; else set --; fi; exec firebase emulators:start --config firebase.emulator.json --project demo-katyuflow --only auth,firestore --export-on-exit=/data/export \"$@\""]
