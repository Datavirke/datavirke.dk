@serve:
    docker run --rm                     \
        -v $(pwd):/site                 \
        --workdir=/site                 \
        -p 3000:3000                    \
        -p 1024:1024                    \
        ghcr.io/getzola/zola:v0.19.2    \
        serve                           \
            --interface 0.0.0.0         \
            --base-url localhost        \
            --port 3000
