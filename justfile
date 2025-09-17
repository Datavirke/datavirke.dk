serve:
    just enter "bundle exec jekyll serve -l --host=0.0.0.0"

enter *args="zsh":
    docker start datavirke
    docker exec -it datavirke {{ args }}

check:
    just enter 'bundle exec htmlproofer _site \
        \-\-disable-external \
        \-\-ignore-urls "/^http:\/\/127.0.0.1/,/^http:\/\/0.0.0.0/,/^http:\/\/localhost/"'

create:
    docker rm datavirke -f
    docker run -d               \
        -v $(pwd):/app          \
        -p 4000:4000            \
        -p 35729:35729          \
        --workdir=/app          \
        --name datavirke        \
        --entrypoint /bin/bash  \
        -e JEKYLL_ENV=production \
         mcr.microsoft.com/devcontainers/jekyll:2-bullseye -c 'sleep 3600'

    just enter "git config --global --add safe.directory /app"
    just enter "bundle install"
    just serve


