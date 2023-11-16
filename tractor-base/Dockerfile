# syntax=docker/dockerfile:1

FROM rockylinux:8.8

# update packages
RUN dnf -y update \
 && dnf install -y sssd-client \
 && dnf clean all

# place PAM definition
COPY sssd-tractor /etc/pam.d/sssd-tractor

WORKDIR /tmp

# install Tractor
COPY Tractor-2.4.x86_64.rpm .
RUN rpm -i ./Tractor-2.4.x86_64.rpm \
 && rm ./Tractor-2.4.x86_64.rpm

# create user
RUN useradd tractor-engine -mrd /home/tractor-engine -s /usr/sbin/nologin

# fix dependencies
RUN ln -s /usr/lib64/libreadline.so.7 /usr/lib64/libreadline.so.6

# set workdir
WORKDIR /home/tractor-engine
