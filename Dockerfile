FROM ghcr.io/getzola/zola:v0.19.2 AS zola
ENV HOSTNAME="datavirke.dk"

COPY . /project
WORKDIR /project
RUN ["zola", "build"]

FROM ghcr.io/static-web-server/static-web-server:2
ENV SERVER_PORT=3000
WORKDIR /
USER 1252:1252
COPY --from=zola --chown=1252:1252 /project/public /public
