#!/bin/bash

set -e
set -u

mkdir system
debootstrap stretch system

# Install perlbrew, and perl-5.24.1
cat > system/install.sh <<'EOF'
#!/bin/bash
set -e
set -u
apt-get install build-essential perlbrew
export PERLBREW_ROOT=/opt/perlbrew
mkdir -p $PERLBREW_ROOT
perlbrew init
perlbrew install perl-5.24.1
perlbrew switch perl-5.24.1
perlbrew install-cpanm
EOF

cat > system/etc/profile.d/perlbrew.sh << EOF
export PERLBREW_ROOT=/opt/perlbrew
EOF

chmod +x system/install.sh

# This should now install perlbrew, switch to perlbrew to 5.24.1, and install cpanm
chroot system /install.sh

echo The system is now ready to be used
