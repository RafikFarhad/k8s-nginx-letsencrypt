#!/bin/bash -
#title          :run.sh
#description    :This script automatically contact to letsencrypt and generate ssl for the domain and update the kubernetes tls secret.
#author         :RafikFarhad<rafikfarhad@gmail.com>
#date           :20200613
#version        :1.0.0
#usage          :./myscript.sh
#notes          :Required env values are: DOMAINS,SECETS,NAMESPACE,EMAIL,CLUSTER_ADDRESS,DO_NOT_UPDATE_WINDOW
#bash_version   :5.0.17(1)-release
# ##################################################
function log() {
    echo "##################################################"
    echo $1
    echo "##################################################"
}
# ##################################################
log "Kubernetes-Nginx-LetsEncrypt Helper Tool"
echo ""
echo ""

DOMAIN_LIST=()
SECRET_LIST=()
COMPLETED=()
NOT_COMPLETED=()

function check_domain_list() {
    if [[ -z $DOMAINS ]]; then
        log "Domain list not found. Specify at least one domain."
        exit 1
    fi
    split_csv $DOMAINS DOMAIN_LIST
}

function check_secret_list() {
    if [[ -z $SECRETS ]]; then
        log "Kubernetes secret list not found."
        exit 1
    fi
    split_csv $SECRETS SECRET_LIST
}

function split_csv() {
    IFS=','
    csv_data=$1
    local -n global_list_array=$2
    for i in $csv_data; do
        global_list_array+=($i)
    done
    unset IFS
}

function check_domain_secret_pair() {
    if [[ ${#DOMAIN_LIST[@]} -ne ${#SECRET_LIST[@]} ]]; then
        log "Domain and Secret count not matched."
        log "Your provided ${#DOMAIN_LIST[@]} domain."
        log "But you provided ${#SECRET_LIST[@]} secret to be updated."
        exit 1
    fi
}

function check_other_inputs() {
    if [[ -z $EMAIL ]]; then
        log "Email not provided."
        exit 1
    fi
    if [[ -z $NAMESPACE ]]; then
        log "Namespace not provided."
        exit 1
    fi
    if [[ -z $CLUSTER_ADDRESS ]]; then
        log "Cluster address not provided. Secret will not be pushed to kubernetes and will be printed on console."
    fi
}

function get_day_to_expire() {
    site=$1
    local -n expired_in=$2
    certificate_file=$(mktemp)
    echo -n | openssl s_client -servername "$site" -connect "$site":443 2>/dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' >$certificate_file
    date=$(openssl x509 -in $certificate_file -enddate -noout | sed "s/.*=\(.*\)/\1/")
    date_s=$(date -d "${date}" +%s)
    now_s=$(date -d now +%s)
    expired_in=$(((date_s - now_s) / 86400))
}

function generate_ssl() {
    domain=$1
    secret=$2
    log "Generating SSL for $domain:"
    EXPIRED_IN=0
    if [ ! -z $DO_NOT_UPDATE_WINDOW ]; then
        get_day_to_expire ${domain} EXPIRED_IN
        log "This domain will expire in ${EXPIRED_IN}"
        if [ ! -z $EXPIRED_IN ] && [ $EXPIRED_IN -gt $DO_NOT_UPDATE_WINDOW ]; then
            log "Skipping domain"
            return
        fi
    fi
    certbot certonly -n \
        --no-self-upgrade \
        --preferred-challenges=http \
        --config-dir /root/.certbot/config \
        --logs-dir /root/.certbot/logs \
        --work-dir /root \
        --webroot --webroot-path /root \
        --agree-tos \
        --server https://acme-v02.api.letsencrypt.org/directory \
        --email ${EMAIL} \
        -d ${domain}

    CERT_PATH="/root/.certbot/config/live/${domain}"

    if [ ! -d $CERT_PATH ]; then
        log "SSL is not generated for ${domain}."
        NOT_COMPLETED+=($domain)
        return
    fi
    cat /root/secret_config_template.json |
        sed "s/NAMESPACE/${NAMESPACE}/" |
        sed "s/NAME/${secret}/" |
        sed "s/TLSCERT/$(cat ${CERT_PATH}/fullchain.pem | base64 | tr -d '\n')/" |
        sed "s/TLSKEY/$(cat ${CERT_PATH}/privkey.pem | base64 | tr -d '\n')/" \
            >/root/secret_config.json

    if [ ! -f /root/secret_config.json ]; then
        log "Secret config not generated for ${domain}."
        NOT_COMPLETED+=($domain)
        return
    fi
    if [ ! -z $CLUSTER_ADDRESS ]; then
        log "Updating secret to kubermetes cluster ..."
        status=$(curl --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
            -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
            -k -XPATCH -H "Accept: application/json, */*" \
            -H "Content-Type: application/strategic-merge-patch+json" \
            -d @/root/secret_config.json \
            -o /dev/stderr \
            -s -w "%{http_code}\n" \
            https://${CLUSTER_ADDRESS}/api/v1/namespaces/${NAMESPACE}/secrets/${secret})
        if [ $status -ne 200 ]; then
            log "Secret not updated for ${domain}: Curl status: ${status}."
            NOT_COMPLETED+=($domain)
            return
        fi
    else 
        cat ./secret_config.json
    fi
    rm ./secret_config.json
    COMPLETED+=($domain)
    log "Secret updated."
}

function generate_ssl_for_all_domains() {
    total_iteration=${#DOMAIN_LIST[@]}
    python -m SimpleHTTPServer 80 &
    sleep 3
    PID=$!
    for ((i = 0; i < total_iteration; i++)); do
        generate_ssl ${DOMAIN_LIST[$i]} ${SECRET_LIST[$i]}
    done
    kill $PID
    sleep 3
}

# Main

check_domain_list
check_secret_list
check_domain_secret_pair
check_other_inputs
generate_ssl_for_all_domains

echo "##################################################"
if [ ${#COMPLETED[@]} -ne 0 ]; then
    echo "SSL generated for:"
    printf "=> %s\n" "${COMPLETED[@]}"
fi
if [ ${#NOT_COMPLETED[@]} -ne 0 ]; then
    echo "SSL not generated for:"
    printf "x => %s\n" "${NOT_COMPLETED[@]}"
fi
echo "##################################################"
log "Task Ended."
exit 0
