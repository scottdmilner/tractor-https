# Pixar's Tractor with HTTPS and FreeIPA/PAM Authentication

A framework for running Pixar's Tractor with HTTPS authentication, allowing 
secure login via FreeIPA or another PAM module. The containers need some 
privileged access, as 

1. The Tractor container relies on the host's FreeIPA enrollment for 
authentication (FreeIPA is picky about the FQDN)
1. Tractor does not respect `X-Forwarded-For` headers, so the proxy container
uses the host network in order to serve as a transparent, TLS-terminating
proxy


# Setup

## Host machine

On the host machine (this has been tested with Rocky 8.8), install Docker and 
Docker Compose. Enroll the host in FreeIPA or another authentication service.
This configuration uses an HBAC (Host-Based Access Control) rule allowing all
users to log in via a custom service named `tractor-sssd`. This allows Tractor 
web console login but restricts login via SSH.

The NGINX container uses iptables to configure its transparent proxy, but does
not have permission to `modprobe` needed kernel modules on the host system. To
enable them on the running system, run `sudo modprobe iptable_mangle x_tables 
xt_mark`

To enable these modules on boot, create the file 
`/etc/modules-load.d/tractor-https.conf` with the following contents:

```
iptable_mangle
x_tables
xt_mark
```


### Tractor Engine configuration

Clone this repo. Place all of your Tractor configuration files in the 
`config/` directory (in this repo). Here is a list of the files Tractor 
expects:

```
blade.config
crews.config
db.config
limits.config
menus.config
postgresql.conf
shared.linux.envkeys
shared.macosx.envkeys
shared.windows.envkeys
tractor.config
trSiteDashboardFunctions.js
trSiteFunctions.py
trSiteLdapLoginValidator.py
trSiteLoginValidator.py
```

To avoid conflicts with the host-networked proxy container listening on port
80, **the Tractor Engine must run on port 8080** (or another port of your
choice, you'd need to configure this manually). To do this, set the 
`ListenerPort` in `config/tractor.config`:

```json
{
    ...
    "ListenerPort": 8080,
    ...
}
```

Create a file named `env` in the main directory. If you plan on using the crew
sync module, define `WRANGLER_GROUP` and `ADMIN_GROUP` here. These are the unix
group names the crew sync service will check. If you use the 
`PIXAR_LICENSE_FILE` variable, you can also define it here. Example 
configuration:

```
ADMIN_GROUP=admin
PIXAR_LICENSE_FILE=9010@licenseserver
WRANGLER_GROUP=wrangler
```

Create a file named `admin_user.txt`. This contains the credentials that the 
crew sync module will use to auto-reload the crews config after the groups
are updated in FreeIPA. Make sure to appropriatly set permissions on this file 
so it can only be seen by the `docker` group and other necessary admin users:

```
username
password
```

Place your Tractor installation RPM obtained from Pixar in the `tractor-base` 
folder. (Docker looks for a file named `Tractor-2.4.x86_64.rpm`)

Name your SSL certificate files `cert.crt` and `cert.key` and place them in
the `certs` folder

After all this, your directory should look like this:

```
.
├── admin_user.txt
├── certs
│   ├── cert.crt
│   └── cert.key
├── config
│   ├── blade.config 
│   ├── crews.config
│   ├── db.config
│   ├── limits.config
│   ├── menus.config
│   ├── postgresql.conf
│   ├── shared.linux.envkeys
│   ├── shared.macosx.envkeys
│   ├── shared.windows.envkeys
│   ├── tractor.config
│   ├── trSiteDashboardFunctions.js
│   ├── trSiteFunctions.py
│   ├── trSiteLdapLoginValidator.py
│   └── trSiteLoginValidator.py
├── crew-sync.sh
├── docker-compose.yml
├── env
├── proxy
│   ├── networking.sh
│   └── nginx.conf
├── README.md
├── tractor-base
│   ├── Dockerfile
│   ├── sssd-tractor
│   └── Tractor-2.4.x86_64.rpm
└── TrHttpRPC.py.patch
```

### FreeIPA Authentication

In `config/crews.config`, change `ValidLogins` to external logins, and set the
`SitePasswordValidator` to `internal:PAM:sssd-tractor`:

```json
{
    ...
    "Crews": {
        "ValidLogins": ["@externlogins"],
        ...
    },
    ...
    "SitePasswordValidator": "internal:PAM:sssd-tractor"
}
```


### Using the crew-sync Module

The crew-sync module checks for updates to the unix groups defined in the `env`
file and populates the files `config/admins` and `config/wranglers` with those
usernames. To include these files into your `config/crews.config` make the 
following changes:

```json
{
    ...
    "Crews": {
    ...
        "Wranglers": ["@merge('wranglers')","hard-coded users or other config"],
        "Administrators": ["@merge('admins')","hard-coded users or other config"]
    },
    ...
}
```

To disable the crew sync module, comment out the `crew-sync` block in 
`docker-compose.yml`.

### Launching Tractor Engine

Finally, you should be able to build and start the containers:

```bash
docker compose build
docker compose up -d
# check that things are running properly
docker compose logs
```


## Tractor Blade Configuration

In order for the Tractor blades to properly communicate with the engine over
SSL, we need to use the beta Python 3 build of Tractor. As of this writing, 
this build can be downloaded from the RenderMan forums. The Python 3 API is 
also included with recent RenderMan Pro Server installations. 

The file `TrHttpRPC.py` needs to be patched to utilize an SSL-secured 
connection using the patch included in this git repo 
(`TrHttpRPC.py.patch`). This relies on the OpenSSL 10 libraries, which
can be installed through the package manager (below commands tested on Rocky 
8.8).

**To patch the RenderMan Pro Server installation:**

```bash
dnf install -y compat-openssl10
patch /opt/pixar/RenderManProServer-XX.Y/bin/tractor/base/TrHttpRPC.py ./TrHttpRPC.py.patch
```

**To patch the Tractor 3 beta blade:**

```bash
dnf install -y compat-openssl10
# as of this writing, the beta build is `tractor-blade3b1.2308.pyz`
# unzip the tractor-blade python executable
mkdir tractor-blade3b1.2308
unzip tractor-blade3b1.2308.pyz -d tractor-blade3b1.2308
cd tractor-blade3b1.2308
# patch the file
patch ./TrHttpRPC.py path/to/TrHttpRPC.py.patch
# re-zip the executable (this assumes that you have rmanpy3 in your PATH)
cd ../
rmanpy3 -m zipapp tractor-blade3b1.2308 -p '/usr/bin/env rmanpy3'
```

In the flags for the `tractor-blade` process (configured via sysconfig or 
otherwise), make sure to specify the port number and fully qualified hostname
of the Tractor engine (SSL requires the hostname to be fully qualified), e.g.

```bash
path/to/tractor-blade3b1.pyz --engine=tractor-engine.example.com:443
```
