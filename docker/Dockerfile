FROM alt:p10
WORKDIR /squid
COPY install_docker.sh install_docker.sh
EXPOSE 3128 3129
CMD bash install_docker.sh && bash /scripts/custom-network.sh
