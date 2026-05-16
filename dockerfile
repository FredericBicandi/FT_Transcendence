FROM node:22-alpine

WORKDIR /app

RUN apk add --no-cache nginx openssl

COPY package*.json ./
RUN npm install

COPY . .
RUN npm run build

RUN mkdir -p /etc/nginx/ssl

RUN openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/selfsigned.key \
    -out /etc/nginx/ssl/selfsigned.crt \
    -subj "/C=LB/ST=Beirut/L=Beirut/O=ft_transcendence/CN=0.0.0.0"

COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 443

CMD sh -c "npm run start -- -H 0.0.0.0 -p 3000 & nginx -g 'daemon off;'"

