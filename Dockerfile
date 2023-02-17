FROM python:3.10-slim-bullseye
ARG HTCONDOR_RELEASE=10.x
ARG HTCONDOR_VERSION=10.2.1

# set up adstash user
ENV ADSTASH_USER=adstash
ENV ADSTASH_HOME=/home/${ADSTASH_USER}
ENV ADSTASH_CONFIG=${ADSTASH_HOME}/adstash_config
ENV ADSTASH_PATH=/opt/condor_adstash
ENV ADSTASH_BIN=${ADSTASH_PATH}/bin
ENV ADSTASH_LIB=${ADSTASH_PATH}/lib
RUN useradd -md ${ADSTASH_HOME} ${ADSTASH_USER}

# install external Python libraries
ADD requirements.txt /tmp/requirements.txt
RUN sed -i s/HTCONDOR_VERSION/${HTCONDOR_VERSION}/ /tmp/requirements.txt
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r /tmp/requirements.txt && \
    rm /tmp/requirements.txt

# install packages
RUN apt-get update && \
    apt-get install -y curl supervisor && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# install condor_adstash from the source tree
ARG HTCONDOR_TARBALL=https://research.cs.wisc.edu/htcondor/tarball/${HTCONDOR_RELEASE}/${HTCONDOR_VERSION}/release/condor-${HTCONDOR_VERSION}-src.tar.gz
RUN mkdir -p ${ADSTASH_PATH}/bin ${ADSTASH_PATH}/lib && \
    curl -k -L ${HTCONDOR_TARBALL} > /tmp/htcondor.tar.gz && \
    tar -xf /tmp/htcondor.tar.gz --strip-components=1 --directory=/tmp && \
    mv /tmp/src/condor_scripts/condor_adstash ${ADSTASH_BIN} && \
    mv /tmp/src/condor_scripts/adstash ${ADSTASH_LIB} && \
    rm -rf /tmp/* && \
    chmod 0755 ${ADSTASH_BIN}/condor_adstash

# set up supervisord
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
CMD ["/usr/bin/supervisord"]

# set up condor config
COPY adstash_config ${ADSTASH_CONFIG}
RUN chown ${ADSTASH_USER}:${ADSTASH_USER} ${ADSTASH_CONFIG}

# test imports
RUN PYTHONPATH=$PYTHONPATH:${ADSTASH_LIB} python -c "import htcondor; import elasticsearch; import adstash"
