FROM ghcr.io/hostinger/fireactions-images/ubuntu24.04:latest

# Create global Maven settings directory
RUN mkdir -p /usr/share/maven/conf /etc/maven

# Create a settings.xml that points to your local proxy
RUN echo '<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0" \
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" \
  xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 https://maven.apache.org/xsd/settings-1.0.0.xsd"> \
  <mirrors> \
    <mirror> \
      <id>local-cache</id> \
      <name>Local Nginx Cache</name> \
      <url>https://maven.coded.page/</url> \
      <mirrorOf>*</mirrorOf> \
    </mirror> \
  </mirrors> \
</settings>' > /etc/maven/settings.xml

# Configure Clojure tools (deps.edn / tools.build) to use the proxy
# Note: Clojure CLI strictly requires https for repositories by default.
# We can bypass this by explicitly allowing HTTP using an environment variable or JVM arg,
# but it's easier to just use the Nginx proxy via HTTPS using a dummy domain we resolve locally.
# Let's use the local Nginx proxy via HTTPS by telling dnsmasq to resolve maven.coded.page to 10.200.0.1
RUN mkdir -p /root/.clojure /home/runner/.clojure && \
    echo '{:mvn/local-repo "/home/runner/.m2/repository" \
 :mvn/repos {"central" {:url "https://maven.coded.page/"} \
             "clojars" {:url "https://maven.coded.page/repo/"}}}' | tee /root/.clojure/deps.edn /home/runner/.clojure/deps.edn

# Configure Leiningen to use the proxy
RUN mkdir -p /root/.lein /home/runner/.lein && \
    echo '{:mirrors {"central" {:name "central" :url "https://maven.coded.page/"} \
             "clojars" {:name "clojars" :url "https://maven.coded.page/repo/"}}}' | tee /root/.lein/profiles.clj /home/runner/.lein/profiles.clj && \
    chown -R runner:runner /home/runner/.clojure /home/runner/.lein

# Ensure iptables legacy is used for docker compatibility inside the VM
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy || true && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy || true

# The Firecracker VM kernel doesn't have CONFIG_IP_NF_RAW compiled in, so Docker's
# "DIRECT ACCESS FILTERING" feature fails. Disable it via the environment variable
# introduced in Docker 28.0.2 (https://github.com/moby/moby/pull/49621).
RUN mkdir -p /etc/systemd/system/docker.service.d && \
    printf '[Service]\nEnvironment="DOCKER_INSECURE_NO_IPTABLES_RAW=1"\n' \
    > /etc/systemd/system/docker.service.d/no-iptables-raw.conf
