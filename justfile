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

@build:
    docker build -t registry.kronform.pius.dev/datavirke.dk/datavirke.dk:main .
    docker push registry.kronform.pius.dev/datavirke.dk/datavirke.dk:main

@deploy:
    kubectl apply -f deploy/deployment.yaml
    kubectl rollout restart deployment -n datavirke-website datavirke-dk
    kubectl rollout status deployment -n datavirke-website datavirke-dk