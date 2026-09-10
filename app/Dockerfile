FROM node:18-alpine
WORKDIR /app
COPY package.json .
COPY app.js .
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost:3000/health || exit 1
CMD ["node", "app.js"]
