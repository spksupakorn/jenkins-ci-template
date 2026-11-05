# Jenkins + Docker CLI/Buildx/Compose + ssh client
# ใช้ Docker daemon ของ host ผ่าน /var/run/docker.sock (ไม่ใช่ Docker-in-Docker)
FROM jenkins/jenkins:lts-jdk21

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg openssh-client \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
 && chmod a+r /etc/apt/keyrings/docker.asc \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin docker-compose-plugin \
 && rm -rf /var/lib/apt/lists/*

USER jenkins

# plugin ที่ pipeline นี้ใช้ (เพิ่มจาก suggested plugins)
RUN jenkins-plugin-cli --plugins \
      gitlab-plugin \
      ssh-agent \
      git \
      workflow-aggregator \
      credentials-binding \
      timestamper
