FROM ghcr.io/hostinger/fireactions-images/ubuntu24.04:latest

# Point apt at Nexus proxy repos via the local HTTPS domain.
# Nexus passes through the original Ubuntu GPG signatures (no re-signing),
# so the base image's Ubuntu keyring works as-is.
RUN printf \
    "deb https://cache.coded.page/repository/apt-proxy/ noble main restricted universe multiverse\n\
deb https://cache.coded.page/repository/apt-proxy/ noble-updates main restricted universe multiverse\n\
deb https://cache.coded.page/repository/apt-security/ noble-security main restricted universe multiverse\n" \
    > /etc/apt/sources.list && \
    rm -f /etc/apt/sources.list.d/*.list

# Create global Maven settings directory
RUN mkdir -p /usr/share/maven/conf /etc/maven

# Point Maven to the Nexus maven-public group repo (proxies Maven Central + Clojars).
RUN echo '<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0" \
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" \
  xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 https://maven.apache.org/xsd/settings-1.0.0.xsd"> \
  <mirrors> \
    <mirror> \
      <id>nexus</id> \
      <name>Nexus Cache</name> \
      <url>https://cache.coded.page/repository/maven-public/</url> \
      <mirrorOf>*</mirrorOf> \
    </mirror> \
  </mirrors> \
</settings>' > /etc/maven/settings.xml

# Configure Clojure tools (deps.edn / tools.build) to use the Nexus maven-public group.
# Both central and clojars point to the same group repo — Nexus serves both.
RUN mkdir -p /root/.clojure /home/runner/.clojure && \
    echo '{:mvn/local-repo "/home/runner/.m2/repository" \
 :mvn/repos {"central" {:url "https://cache.coded.page/repository/maven-public/"} \
             "clojars" {:url "https://cache.coded.page/repository/maven-public/"}}}' | tee /root/.clojure/deps.edn /home/runner/.clojure/deps.edn

# Configure Leiningen to use the Nexus maven-public group.
RUN mkdir -p /root/.lein /home/runner/.lein && \
    echo '{:mirrors {"central" {:name "central" :url "https://cache.coded.page/repository/maven-public/"} \
             "clojars" {:name "clojars" :url "https://cache.coded.page/repository/maven-public/"}}}' | tee /root/.lein/profiles.clj /home/runner/.lein/profiles.clj && \
    chown -R runner:runner /home/runner/.clojure /home/runner/.lein

# Configure npm to use the Nexus npm proxy by writing .npmrc directly
# (npm is not installed in the base image at build time).
RUN echo "registry=https://cache.coded.page/repository/npm-proxy/" \
    | tee /root/.npmrc /home/runner/.npmrc && \
    chown runner:runner /home/runner/.npmrc

# Ensure iptables legacy is used for docker compatibility inside the VM
# Also install libnss-myhostname so Java can resolve the dynamically generated VM hostname
RUN apt-get update && \
    apt-get install -y --no-install-recommends libnss-myhostname && \
    rm -rf /var/lib/apt/lists/* && \
    update-alternatives --set iptables /usr/sbin/iptables-legacy || true && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy || true

# The Firecracker VM kernel doesn't have CONFIG_IP_NF_RAW compiled in, so Docker's
# "DIRECT ACCESS FILTERING" feature fails. Disable it via the environment variable
# introduced in Docker 28.0.2 (https://github.com/moby/moby/pull/49621).
RUN mkdir -p /etc/systemd/system/docker.service.d && \
    printf '[Service]\nEnvironment="DOCKER_INSECURE_NO_IPTABLES_RAW=1"\n' \
    > /etc/systemd/system/docker.service.d/no-iptables-raw.conf
