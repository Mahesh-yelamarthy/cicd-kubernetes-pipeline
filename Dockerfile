FROM nginxinc/nginx-unprivileged:1.27-alpine

LABEL org.opencontainers.image.title="cicd-kubernetes-pipeline"
LABEL org.opencontainers.image.description="Static demo workload for Kubernetes CI/CD pipeline validation"
LABEL org.opencontainers.image.source="https://github.com/Mahesh-yelamarthy/cicd-kubernetes-pipeline"

COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY app/ /usr/share/nginx/html/

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
