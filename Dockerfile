ARG NAMESPACE=selenium
ARG VERSION=latest
FROM ${NAMESPACE}/node-base:${VERSION}
ARG AUTHORS
LABEL authors=${AUTHORS}

USER root

#============================================
# Google Chrome
#============================================
# can specify versions by CHROME_VERSION;
#  e.g. google-chrome-stable
#       google-chrome-beta
#       google-chrome-unstable
#============================================
ARG CHROME_VERSION="google-chrome-stable"
RUN wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor | tee /etc/apt/trusted.gpg.d/google.gpg >/dev/null \
  && echo "deb http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list \
  && apt-get update -qqy \
  && if echo "${CHROME_VERSION}" | grep -qE "google-chrome-stable[_|=][0-9]*"; \
    then \
      CHROME_VERSION=$(echo "$CHROME_VERSION" | tr '=' '_') \
      && wget -qO google-chrome.deb "https://dl.google.com/linux/chrome/deb/pool/main/g/google-chrome-stable/${CHROME_VERSION}_$(dpkg --print-architecture).deb" \
      && apt-get -qqy --no-install-recommends install --allow-downgrades ./google-chrome.deb \
      && rm -rf google-chrome.deb ; \
    else \
      apt-get -qqy --no-install-recommends install ${CHROME_VERSION} ; \
    fi \
  && rm /etc/apt/sources.list.d/google-chrome.list \
  && rm -rf /var/lib/apt/lists/* /var/cache/apt/*

#=================================
# Chrome Launch Script Wrapper
#=================================
COPY wrap_chrome_binary /opt/bin/wrap_chrome_binary
RUN /opt/bin/wrap_chrome_binary

#============================================
# Chrome webdriver
#============================================
# can specify versions by CHROME_DRIVER_VERSION
# Latest released version will be used by default
#============================================
ARG CHROME_DRIVER_VERSION
RUN DRIVER_ARCH=$(if [ "$(dpkg --print-architecture)" = "amd64" ]; then echo "linux64"; else echo "linux-aarch64"; fi) \
  && if [ ! -z "$CHROME_DRIVER_VERSION" ]; \
  then CHROME_DRIVER_URL=https://storage.googleapis.com/chrome-for-testing-public/$CHROME_DRIVER_VERSION/${DRIVER_ARCH}/chromedriver-${DRIVER_ARCH}.zip ; \
  else CHROME_MAJOR_VERSION=$(google-chrome --version | sed -E "s/.* ([0-9]+)(\.[0-9]+){3}.*/\1/") \
    && echo "Geting ChromeDriver latest version from https://googlechromelabs.github.io/chrome-for-testing/LATEST_RELEASE_${CHROME_MAJOR_VERSION}" \
    && CHROME_DRIVER_VERSION=$(wget -qO- https://googlechromelabs.github.io/chrome-for-testing/LATEST_RELEASE_${CHROME_MAJOR_VERSION} | sed 's/\r$//') \
    && CHROME_DRIVER_URL=https://storage.googleapis.com/chrome-for-testing-public/$CHROME_DRIVER_VERSION/${DRIVER_ARCH}/chromedriver-${DRIVER_ARCH}.zip ; \
  fi \
  && echo "Using ChromeDriver from: "$CHROME_DRIVER_URL \
  && echo "Using ChromeDriver version: "$CHROME_DRIVER_VERSION \
  && wget --no-verbose -O /tmp/chromedriver_${DRIVER_ARCH}.zip $CHROME_DRIVER_URL \
  && rm -rf /opt/selenium/chromedriver \
  && unzip /tmp/chromedriver_${DRIVER_ARCH}.zip -d /opt/selenium \
  && rm /tmp/chromedriver_${DRIVER_ARCH}.zip \
  && mv /opt/selenium/chromedriver-${DRIVER_ARCH}/chromedriver /opt/selenium/chromedriver-$CHROME_DRIVER_VERSION \
  && chmod 755 /opt/selenium/chromedriver-$CHROME_DRIVER_VERSION \
  && ln -fs /opt/selenium/chromedriver-$CHROME_DRIVER_VERSION /usr/bin/chromedriver

#============================================
# Chrome cleanup script and supervisord file
#============================================
COPY chrome-cleanup.sh /opt/bin/chrome-cleanup.sh
COPY chrome-cleanup.conf /etc/supervisor/conf.d/chrome-cleanup.conf


#=========
# Firefox
#=========
ARG FIREFOX_VERSION=latest
RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
        FIREFOX_DOWNLOAD_URL=$(if [ $FIREFOX_VERSION = "latest" ] || [ $FIREFOX_VERSION = "beta-latest" ] || [ $FIREFOX_VERSION = "nightly-latest" ] || [ $FIREFOX_VERSION = "devedition-latest" ] || [ $FIREFOX_VERSION = "esr-latest" ]; then echo "https://download.mozilla.org/?product=firefox-$FIREFOX_VERSION-ssl&os=linux64&lang=en-US"; else echo "https://download-installer.cdn.mozilla.net/pub/firefox/releases/$FIREFOX_VERSION/linux-x86_64/en-US/firefox-$FIREFOX_VERSION.tar.bz2"; fi) ; \
    else \
        FIREFOX_DOWNLOAD_URL="https://download.mozilla.org/?product=firefox-nightly-latest-ssl&os=linux64-aarch64&lang=en-US" ; \
    fi \
  && apt-get update -qqy \
  && apt-get -qqy --no-install-recommends install libavcodec-extra libgtk-3-dev libdbus-glib-1-dev \
  && rm -rf /var/lib/apt/lists/* /var/cache/apt/* ${HOME}/firefox \
  && wget --no-verbose -O /tmp/firefox.tar.bz2 $FIREFOX_DOWNLOAD_URL \
  && tar -C ${HOME} -xjf /tmp/firefox.tar.bz2 \
  && rm /tmp/firefox.tar.bz2 \
  && mkdir -p ${HOME}/firefox/distribution/extensions \
  && setfacl -Rm u:${SEL_USER}:rwx ${HOME}/firefox \
  && setfacl -Rm g:${SEL_GROUP}:rwx ${HOME}/firefox \
  && ln -fs ${HOME}/firefox/firefox /usr/bin/firefox

#============
# GeckoDriver
#============
ARG GECKODRIVER_VERSION=latest
RUN LATEST_VERSION=$(curl -sk https://api.github.com/repos/mozilla/geckodriver/releases/latest | jq -r '.tag_name') \
  && DRIVER_ARCH=$(if [ "$(dpkg --print-architecture)" = "amd64" ]; then echo "linux64"; else echo "linux-aarch64"; fi) \
  && GK_VERSION=$(if [ ${GECKODRIVER_VERSION:-latest} = "latest" ]; then echo "${LATEST_VERSION}"; else echo $GECKODRIVER_VERSION; fi) \
  && echo "Using GeckoDriver version: "$GK_VERSION \
  && wget --no-verbose -O /tmp/geckodriver.tar.gz https://github.com/mozilla/geckodriver/releases/download/${GK_VERSION}/geckodriver-${GK_VERSION}-${DRIVER_ARCH}.tar.gz \
  && rm -rf /opt/geckodriver \
  && tar -C /opt -zxf /tmp/geckodriver.tar.gz \
  && rm /tmp/geckodriver.tar.gz \
  && mv /opt/geckodriver /opt/geckodriver-$GK_VERSION \
  && chmod 755 /opt/geckodriver-$GK_VERSION \
  && ln -fs /opt/geckodriver-$GK_VERSION /usr/bin/geckodriver

#============================================
# Firefox cleanup script and supervisord file
#============================================
COPY --chown="${SEL_UID}:${SEL_GID}" firefox-cleanup.sh get_lang_package.sh /opt/bin/
COPY --chown="${SEL_UID}:${SEL_GID}" firefox-cleanup.conf /etc/supervisor/conf.d/firefox-cleanup.conf
RUN chmod +x /opt/bin/firefox-cleanup.sh /opt/bin/get_lang_package.sh


#============================================
# Microsoft Edge
#============================================
# can specify versions by EDGE_VERSION;
#  e.g. microsoft-edge-beta=88.0.692.0-1
#============================================
ARG EDGE_VERSION="microsoft-edge-stable"
RUN wget -q -O - https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg >/dev/null \
  && echo "deb https://packages.microsoft.com/repos/edge stable main" >> /etc/apt/sources.list.d/microsoft-edge.list \
  && apt-get update -qqy \
  && if echo "${EDGE_VERSION}" | grep -qE "microsoft-edge-stable[_|=][0-9]*"; \
    then \
      EDGE_VERSION=$(echo "$EDGE_VERSION" | tr '=' '_') \
      && wget -qO microsoft-edge.deb "https://packages.microsoft.com/repos/edge/pool/main/m/microsoft-edge-stable/${EDGE_VERSION}_$(dpkg --print-architecture).deb" \
      && apt-get -qqy --no-install-recommends install --allow-downgrades ./microsoft-edge.deb \
      && rm -rf microsoft-edge.deb ; \
    else \
      apt-get -qqy --no-install-recommends install ${EDGE_VERSION} ; \
    fi \
  && rm /etc/apt/sources.list.d/microsoft-edge.list \
  && rm -rf /var/lib/apt/lists/* /var/cache/apt/*

#=================================
# Edge Launch Script Wrapper
#=================================
COPY wrap_edge_binary /opt/bin/wrap_edge_binary
RUN /opt/bin/wrap_edge_binary

#============================================
# Edge webdriver
#============================================
# can specify versions by EDGE_DRIVER_VERSION
# Latest released version will be used by default
#============================================
ARG EDGE_DRIVER_VERSION
RUN DRIVER_ARCH=$(if [ "$(dpkg --print-architecture)" = "amd64" ]; then echo "linux64"; else echo "linux-aarch64"; fi) \
  && if [ -z "$EDGE_DRIVER_VERSION" ]; \
  then EDGE_MAJOR_VERSION=$(microsoft-edge --version | sed -E "s/.* ([0-9]+)(\.[0-9]+){3}.*/\1/") \
    && EDGE_DRIVER_VERSION=$(wget --no-verbose -O - "https://msedgedriver.azureedge.net/LATEST_RELEASE_${EDGE_MAJOR_VERSION}_LINUX" | tr -cd "\11\12\15\40-\176" | tr -d "\r"); \
  fi \
  && echo "Using msedgedriver version: "$EDGE_DRIVER_VERSION \
  && wget --no-verbose -O /tmp/msedgedriver_${DRIVER_ARCH}.zip https://msedgedriver.azureedge.net/$EDGE_DRIVER_VERSION/edgedriver_${DRIVER_ARCH}.zip \
  && rm -rf /opt/selenium/msedgedriver \
  && unzip /tmp/msedgedriver_${DRIVER_ARCH}.zip -d /opt/selenium \
  && rm /tmp/msedgedriver_${DRIVER_ARCH}.zip \
  && mv /opt/selenium/msedgedriver /opt/selenium/msedgedriver-$EDGE_DRIVER_VERSION \
  && chmod 755 /opt/selenium/msedgedriver-$EDGE_DRIVER_VERSION \
  && ln -fs /opt/selenium/msedgedriver-$EDGE_DRIVER_VERSION /usr/bin/msedgedriver

#============================================
# Edge cleanup script and supervisord file
#============================================
COPY edge-cleanup.sh /opt/bin/edge-cleanup.sh
COPY edge-cleanup.conf /etc/supervisor/conf.d/edge-cleanup.conf


USER ${SEL_UID}
ENV EDGE_VERSION=${EDGE_VERSION}
ENV CHROME_VERSION=${CHROME_VERSION}
ENV FIREFOX_VERSION=${FIREFOX_VERSION}
