FROM python:3.11-slim-bookworm
ARG HTCONDOR_RELEASE=23.x
ARG HTCONDOR_VERSION=23.7.2
ARG ELASTICSEARCHPY_VERSION=8.14.0

# set up adstash user
ENV ADSTASH_USER=adstash
ENV ADSTASH_HOME=/home/${ADSTASH_USER}
ENV ADSTASH_CONFIG=${ADSTASH_HOME}/adstash_config
ENV ADSTASH_PATH=/opt/condor_adstash
ENV ADSTASH_BIN=${ADSTASH_PATH}/bin
ENV ADSTASH_LIB=${ADSTASH_PATH}/lib
ENV ADSTASH_TIMEOUT=1200
ENV ADSTASH_ARGS=
RUN useradd -md ${ADSTASH_HOME} ${ADSTASH_USER}

# install system packages
RUN apt-get update && \
    apt-get install -y git curl supervisor && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# install external Python libraries
ADD requirements.txt /tmp/requirements.txt
RUN sed -i s/HTCONDOR_VERSION/${HTCONDOR_VERSION}/ /tmp/requirements.txt
RUN sed -i s/ELASTICSEARCHPY_VERSION/${ELASTICSEARCHPY_VERSION}/ /tmp/requirements.txt
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r /tmp/requirements.txt && \
    rm /tmp/requirements.txt
ENV CONDOR_PYTHON_LIB=

# install condor_adstash
ARG HTCONDOR_TARBALL=https://research.cs.wisc.edu/htcondor/tarball/${HTCONDOR_RELEASE}/${HTCONDOR_VERSION}/release/condor-${HTCONDOR_VERSION}-src.tar.gz
ARG TMPDIR=/tmp/setup
COPY adstash_patches.patch $TMPDIR/adstash_patches.patch
RUN mkdir -p ${TMPDIR} ${ADSTASH_PATH}/bin ${ADSTASH_PATH}/lib && \
    curl -k -L ${HTCONDOR_TARBALL} > ${TMPDIR}/htcondor.tar.gz && \
    tar -xf ${TMPDIR}/htcondor.tar.gz --strip-components=1 --directory=${TMPDIR} && \
    git apply --directory ${TMPDIR} --unsafe-paths ${TMPDIR}/adstash_patches.patch && \
    mv ${TMPDIR}/src/condor_scripts/condor_adstash ${ADSTASH_BIN} && \
    mv ${TMPDIR}/src/condor_scripts/adstash ${ADSTASH_LIB} && \
    rm -rf ${TMPDIR} && \
    chmod 0755 ${ADSTASH_BIN}/condor_adstash

# set up supervisord
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY exit_supervisord.sh /exit_supervisord.sh
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]

# set up condor config
COPY adstash_config ${ADSTASH_CONFIG}
RUN chown ${ADSTASH_USER}:${ADSTASH_USER} ${ADSTASH_CONFIG}

# override bindings with preview build
RUN pip uninstall -y htcondor && \
    mkdir -p /opt/condor && \
    curl -k -L https://research.cs.wisc.edu/htcondor/tarball/current/23.8.0/update/condor-23.8.0-x86_64_Debian12-stripped.tar.gz > /opt/condor/htcondor.tar.gz && \
    tar -xf /opt/condor/htcondor.tar.gz --strip-components=1 --directory=/opt/condor && \
    rm /opt/condor/htcondor.tar.gz
ENV CONDOR_PYTHON_LIB=/opt/condor/usr/lib/python3

# test imports
RUN PYTHONPATH=$PYTHONPATH:${ADSTASH_LIB}:${CONDOR_PYTHON_LIB} python -c "import htcondor; import elasticsearch; import adstash"
