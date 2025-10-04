#
# Basic Parameters
#
ARG ARCH="x86_64"
ARG OS="linux"
ARG VER="4.14.5"
ARG PKG="samba-rpms"

ARG BASE_REPO="rockylinux"
ARG BASE_VER="8.5"
ARG BASE_IMG="${BASE_REPO}:${BASE_VER}"

#
# To build the RPMs
#
FROM "${BASE_IMG}" AS builder

#
# Basic Parameters
#
ARG ARCH
ARG OS
ARG VER
ARG PKG
ARG BASE_VER

#
# Some important labels
#
LABEL ORG="ArkCase LLC"
LABEL MAINTAINER="ArkCase Support <support@arkcase.com>"
LABEL APP="Samba RPM Builder"
LABEL VERSION="${VER}"

#
# Full update
#
RUN yum -y install epel-release
RUN yum -y update
RUN yum -y install yum-utils rpm-build which

#
# Enable the required repositories
#
RUN yum-config-manager \
        --enable devel \
        --enable powertools

#
# Final tools needed
#
RUN yum -y install wget
COPY --chown=root:root --chmod=0755 download-srpm find-latest-srpm get-dist /usr/local/bin/

#
# Download the requisite SRPMs
#
WORKDIR /root/rpmbuild
RUN download-srpm "${BASE_VER}/BaseOS" "samba-*.src.rpm" "libldb-*.src.rpm"
#
# We have the RPMs we need, now find the latest ones and build them
#

#
# Build the one missing build dependency - python3-ldb-devel
#
RUN LIBLDB_SRPM="$( find-latest-srpm libldb-*.src.rpm )" && \
    if [ -z "${LIBLDB_SRPM}" ] ; then echo "No libldb SRPM was found" ; exit 1 ; fi && \
    yum-builddep -y "${LIBLDB_SRPM}" && \
    rpmbuild --clean --rebuild "${LIBLDB_SRPM}"

#
# Create a repository that facilitates installation later
#
RUN yum -y install createrepo
RUN createrepo RPMS
COPY arkcase.repo /etc/yum.repos.d
RUN ln -svf $(readlink -f RPMS) /rpm

RUN yum -y install python3-ldb python3-ldb-devel

#
# First things first - which dist is this for?
#
ENV DIST_STR="/.dist"
RUN SAMBA_SRPM="$( find-latest-srpm samba-*.src.rpm )" && \
    if [ -z "${SAMBA_SRPM}" ] ; then echo "No Samba SRPM was found" ; exit 1 ; fi && \
    DIST="$(get-dist "${SAMBA_SRPM}")" && \
    if [ -z "${DIST}" ] ; then echo "Failed to identify the distribution for the SRPM [${SAMBA_SRPM}]" ; exit 1 ; fi && \
    echo -n "${DIST}" > "${DIST_STR}"

#
# Build Samba now
#
RUN SAMBA_SRPM="$( find-latest-srpm samba-*.src.rpm )" && \
    yum-builddep -y "${SAMBA_SRPM}" && \
    yum -y install \
        bind \
        krb5-server \
        ldb-tools \
        python3-cryptography \
        python3-iso8601 \
        python3-markdown \
        python3-pyasn1 \
        python3-setproctitle \
        tdb-tools \
      && \
    DIST="$( cat "${DIST_STR}" )" && \
    rpmbuild --clean --define "dist .${DIST}" --define "${DIST} 1" --with dc --rebuild "${SAMBA_SRPM}"
RUN rm -rf RPMS/repodata
RUN createrepo RPMS

#
# Create an empty image just with the RPMS directory
#
FROM scratch

COPY --from=builder /root/rpmbuild/RPMS /rpm
