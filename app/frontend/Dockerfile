FROM nginx:1.25-alpine

# Remove default nginx config
RUN rm /etc/nginx/conf.d/default.conf

# Backend the /api/ proxy points at. Default suits docker-compose (api:8080).
# In Kubernetes the api Service listens on :80, so the Deployment overrides
# API_URL with the in-cluster Service URL.
ENV API_URL=http://api:8080

# Config is a template: the official nginx entrypoint runs envsubst over
# /etc/nginx/templates/*.template at startup, injecting API_URL and the
# resolver exported by 16-set-api-resolver.envsh.
COPY default.conf.template /etc/nginx/templates/default.conf.template
COPY docker-entrypoint.d/16-set-api-resolver.envsh /docker-entrypoint.d/16-set-api-resolver.envsh
RUN chmod +x /docker-entrypoint.d/16-set-api-resolver.envsh

COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80

# Inherit the base image entrypoint (template rendering + resolver script);
# CMD stays the default nginx launch.
CMD ["nginx", "-g", "daemon off;"]
