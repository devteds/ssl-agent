# Automate SSL Certificate creation and renewal with Docker

Dockerization of ACME client implementation that can be used to automate creating and renewal of SSL certificates. It uses [acme-client](https://github.com/unixcharles/acme-client), a client implementation of [ACME](https://letsencrypt.github.io/acme-spec) protocol in ruby.

## References

- ACME Implementation in ruby: https://github.com/unixcharles/acme-client
- ACME (Auomated Certificate Management Environment): https://en.wikipedia.org/wiki/Automated_Certificate_Management_Environment
- Let's Encrypt: https://letsencrypt.org/how-it-works/

## Usage with Docker Compose

### Docker Compose file

- Create a docker-compose.yml file. Below is an example compose file
- Set environment variables in compose servie definition - Refer below for environment variable details
- Map volumes on the docker host for web server doc root and a directory for certs

```
version: '3'
services:
  ssl-agent:
    image: devteds/ssl-agent:latest
    environment:
      LETSENCRYPT_ENV: staging
      CONTACT_EMAIL: youremailaddress@domain.xxx
      DOMAIN_NAMES: devteds.xyz
    volumes:
      - "/root/website/html:/ssl-agent/webserver-root:rw"
      - "/root/website/certs:/ssl-agent/certs:rw"
```

### Docker Host

If you are using Docker Machine, set docker environment variables to point to the docker host where you have your web-server running.

```
eval $(docker-machine env <MACHINE NAME>)
```

The nginx doc root and certs folder should be as mentioned under volumes in the compose service 'ssl-agent' definition. Update otherwise.

### Create new certificate

This will require two types of private keys. One for the certificate and other for registering with Let's Encrypt as well as for Domain Validation process. If you have private keys, copy those files in the certs directory and set environment variables ACCT_PRIVATE_KEY_FILENAME and CERT_PRIVATE_KEY_FILENAME in the compose file.

If you don't have private keys, this command will first generate private keys for both account registration and certificate.

```
docker-compose run --rm ssl-agent create
```

This will place the certificate file under certs folder. Also, if you it generated the private keys, those will be placed in certs folder. It will not delete or move private keys if you supplied any.


### Renew certificate

This will skip the account registration step but will check if the domain names are verified. This will require both the private keys that was used or created when the certificate was created.

Make sure the private keys are placed under certs directory. If you don't have the previous private keys, you might want to create a new one instead of attempting to renew.

```
docker-compose run --rm ssl-agent renew
```

## Usage with Docker command (not using Docker Compose)

Follow the same notes as described for creation and renewal with docker compose above.

You can either run the docker command remotely by setting DOCKER_HOST environment or with docker machine environment variables. 

```
eval $(docker-machine env <MACHINE NAME>)
```

Or you can run the commands directly on the docker host where you have your webserver is running.

```
docker-machine ssh <MACHINE NAME>
# or ssh to server
```

### Create new certificate

```
docker run -it -e LETSENCRYPT_ENV=staging -e DOMAIN_NAMES=YOURDOMAIN.COM -e CONTACT_EMAIL=YOURMEMAIL@DOMAIN.COMM -v "<NGINX ROOT ON DOCKER HOST>:/ssl-agent/webserver-root:rw" -v "<DIRECTORY FOR CERTS & KEYS>:/ssl-agent/certs:rw" devteds/ssl-agent:latest create
```

### Renew certificate

```
docker run -it -e LETSENCRYPT_ENV=staging -e DOMAIN_NAMES=YOURDOMAIN.COM -e CONTACT_EMAIL=YOURMEMAIL@DOMAIN.COMM -v "<NGINX ROOT ON DOCKER HOST>:/ssl-agent/webserver-root:rw" -v "<DIRECTORY FOR CERTS & KEYS>:/ssl-agent/certs:rw" devteds/ssl-agent:latest renew
```

## Environment Variables

**LETSENCRYPT_ENV**

Values can either be prod or staging. Use staging while you test the process. Certificates issues on Let's Encrypt staging are not trusted ones or are more like self-signed but it will let you test the automation of SSL cert creation and renewal. Use 'prod' when you configure for prod. Below is how it maps to Let's Encrypt API endpoints

- staging: https://acme-staging.api.letsencrypt.org/
- prod:  https://acme-v01.api.letsencrypt.org/

**CONTACT_EMAIL**

Email address for account registration with Let's Encrypt

**DOMAIN_NAMES**

Command seperated domain names that you want to create or renew certificates for. These domain names should resolve to the web server (nginx) that serves resources from the root directory that you mapped under volumes for '/ssl-agent/webserver-root'

**ACCT_PRIVATE_KEY_FILENAME**

*Default:* acct_private_key.pem

File name of the private key used for account registration and domain verification. You may either supply a private key or let ssl-agent generate one. If you would like to supply one, set this environment variable with the file name and place the file in the certificates directory that you mounted to '/ssl-agent/certs'

**CERT_PRIVATE_KEY_FILENAME**

*Default:* cert_private_key.pem

File name of the private key used for certificate creation or renewal. You may either supply a private key or let ssl-agent generate one. If you would like to supply one, set this environment variable with the file name and place the file in the certificates directory that you mounted to '/ssl-agent/certs'

**OBTAINED_CERT_FILENAME**

*Default:* cert_fullchain.pem

Name of the generated or renewed certificate. If you would like to name this file differently in your nginx configuration, specify that name. Or you can copy the generated certificate file to a location or path where it gets used by nginx.

## Volumes

**Directory for certs**

This is where ssl-agent container will read and write certificate files to/from.

**Nginx root**

During the domain authorization verification step, ssl-agent will create a folder under this directory ".well-known/acme/" to place the verification challenge file which then Let's Encrypt will try to access using the URL on the domain name you're attempting to generate the certificate for.

This directory should be your nginx root or the root that serves content for '/.well-known/*'

## Customize and build your image

Clone this repo, customize for your needs and build your image

```
docker-compose build
docker tag devteds/ssl-agent:latest <YOUR PRIVATE REGISTRY URL>:latest
# docker tag devteds/ssl-agent:latest devteds/ssl-agent:v1.0
# docker push devteds/ssl-agent:v1.0
# docker push devteds/ssl-agent:latest
docker push <YOUR PRIVATE REGISTRY URL>:latest
```
