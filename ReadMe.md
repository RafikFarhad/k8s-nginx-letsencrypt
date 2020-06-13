# k8s-nginx-letsencrypt

A tool for maintaining SSL certificates and Kubernetes TLS secrets for deployment.

### Application
  If you,
- have deployed your services on kubernetes cluster
- use nginx-ingress service for load balancing
- and want to `letsencrypt` as your SSL provider

then this is a 'must-try' project for you. 

### Responsibility
This project will cover,
- Automatic domain validation for `letsencrypt`
- Automatic update `tls-secret` for your cluster
- Expiry based `ssl` update functionality. 
- All of the above can be done via periodically by kubernetes `Job/CronJob`

## Components

### Service Account
------------------
At first we need a `ServiceAccount` by which our ceertificates will be updaed to our `secrets`. If you already have a `ServiceAccount` which has `patch` permission to `Secrets` api, then you do not need to create a new one. This sample yml show a basic `ServiceAccount` for our job:
```
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    name: ssl-manager
  name: ssl-manager
  namespace: my-namespace
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  labels:
    name: secret-manager
  name: secret-manager
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["patch"]
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  labels:
    name: ssl-secret-binding
  name: ssl-secret-binding
  namespace: my-namespace
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: secret-manager
subjects:
  - kind: ServiceAccount
    name: ssl-manager
    namespace: my-namespace
```

** If you want to only show the certificates rather than updating your `tls-secret` automatically than you do not need a `ServiceAccount`

### Cluster Address
---------
To update `tls-secret` the job needs to know the cluster address in which your `kubeadm` is running. You can simply the address by `kubectl config view -o jsonpath='{.clusters[0].cluster.server}'` or simply `kubectl config view`

** If you want to only show the certificates rather than updating your `tls-secret` automatically than you do not need a `ClusterAddress`

### TLS Secrets

If you are using `nginx-ingress`, you must have using `tls-secret` to provide the ssl certificates to your ingress. If you do not have any `tls-secret`, or want to create `tls-secret` for a new domain, use this sample yml
```
apiVersion: v1
kind: Secret
metadata:
  name: ssl-key-git.example.com # any suitable name
  namespace: my-namespace
data:
  tls.crt: "Cg=="
  tls.key: "Cg=="
  # primarily there is no certificate or key
  # so we are using "Cg==" as the base64 of empty string ("")
type: kubernetes.io/tls

```

and in your ingress file, attach the `tls-secret` by this:
```
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: livecode-ingress
  namespace: my-namespace
spec:
  tls:
  - secretName: ssl-key-git.example.com # tls-secret you created in previous step
  rules:
  - host: git.example.com # your domain
    http:
      paths:
      ... ... ... ...
      # rest of your routing

```

** If you want to only show the certificates rather than updating your `tls-secret` automatically than you do not need a `tls-secret`

## Main Job

- We will create kubernetes `Job` (You can also create a `CronJob`) which will take the `DOMAINS` AND `SECRETS` as CSV array of domains and there consecutive `tls-secret` name to update. You also need to provide `EMAIL` to register your domain to `letsencrypt` and `NAMESPACE` of your services. You can optionally provide `CLUSTER_ADDRESS` to update your `tls-secret` by this job and `DO_NOT_UPDATE_WINDOW` to determine the window for not requesting a new certificate for this number of days. For example, if you set `DO_NOT_UPDATE_WINDOW=10` than any certificates that have been already expired or will expire in the next `10` days, will be updated. This comes very handily when you have to run this `Job` frequently at first.

- `letsencrypt` ssl certificate creation needs to verify domain ownership. This job utilizes the `--preferred-challenges=http` method. So we will create a temporary ingress rule to redirect all your `example.com/.well-known/*` traffic to this job. 

- The following yml will show you a basic implementation:
```
apiVersion: batch/v1
kind: Job
metadata:
  name: letsencrypt-job
  namespace: my-namespace
  labels:
    app: ssl-app
spec:
  template:
    metadata:
      name: letsencrypt
      labels:
        app: ssl-app
    spec:
      serviceAccount: ssl-manager # <- the ServiceAccount you created
      containers:
      - name: letsencrypt-job-pod
        image: registry.hub.docker.com/rafikfarhad/k8s-nginx-letsencrypt:1.0.0
        imagePullPolicy: Always
        ports:
        - containerPort: 80
        env:
        - name: DOMAINS
          value: git.example.com,db.example.com
        - name: SECRETS
          value: ssl-key-git.example.com,ssl-key-db.example.com,
        - name: EMAIL
          value: rafikfarhad@gmail.com
        - name: NAMESPACE
          value: my-namespace
        - name: CLUSTER_ADDRESS
          value: 127.0.0.1 # <- your cluster IP
        - name: DO_NOT_UPDATE_WINDOW
          value: "14" # <- update those domains which have only 2 weeks to expire
      restartPolicy: Never
---
apiVersion: v1
kind: Service
metadata:
  name: letsencrypt-service
  namespace: my-namespace
spec:
  selector:
    app: ssl-app
  type: NodePort
  ports:
  - port: 80
    nodePort: 32100
    name: letsencrypt-port
---
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: letsencrypt-ingress
  namespace: my-namespace
spec:
  rules:
  - host: git.example.com
    http:
      paths:
      - path: /.well-known
        backend:
          serviceName: letsencrypt-service
          servicePort: 80
  - host: db.example.com
    http:
      paths:
      - path: /.well-known
        backend:
          serviceName: letsencrypt-service
          servicePort: 80
```
Thats it. Run this job when you need to update your `ssl-certificates`.

### Hacks

- `letsencrypt` certificates will expire after 90 days. So you can run this as `CronJob` if you want a full automation process.
- Keep an eye to Job logs, you may trigger `letsencrypt` [rate-limitter](https://letsencrypt.org/docs/rate-limits/) if you try to generate bunch of ssl at once or in a week.
- Delete the service and ingress created by this `Job` (But not in `CronJob`).  

### Inspiration
- https://runnable.com/blog/how-to-use-lets-encrypt-on-kubernetes
- https://github.com/sjenning/kube-nginx-letsencrypt


## License
--------
#### GNU GPL v2

[![License: GPL v2](https://img.shields.io/badge/License-GPL%20v2-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)


## From Author
--------
This project is needed for one of my bigger [project](https://github.com/rafikfarhad/sust-oj-k8s) where I have couple of services and domains to access those services. I'm currently this process in my production, but other situations can demand some other observation. If you feel this project needs further optimization, edition, bug-fix feel free to open PR and raise issues.

😀 Thanks for using it. 😀

😀 ব্যবহার করা জন্য ধন্যবাদ 😀