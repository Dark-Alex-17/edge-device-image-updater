FROM crazymax/diun:latest

RUN apk add docker

ENTRYPOINT [ "diun" ]
CMD [ "serve" ]
