FROM ubuntu:18.04

LABEL AUTHOR="RafikFarhad<rafikfarhad@gmail.com>"

RUN apt-get update && \
    apt-get install -y \
    curl \
    certbot && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /root
USER root

COPY ./run.sh run.sh
COPY ./secret_config_template.json secret_config_template.json

RUN chmod +x run.sh

ENTRYPOINT ["bash", "./run.sh"]
