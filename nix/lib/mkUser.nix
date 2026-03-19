# mkUser: Creates /etc/passwd, /etc/group, /etc/shadow entries for a container user.
#
# Usage:
#   mkUser { inherit pkgs; name = "dependabot"; uid = 1000; gid = 1000; home = "/home/dependabot"; }
#
# Returns a derivation whose output contains /etc/passwd, /etc/group, /etc/shadow,
# and the home directory.
{
  pkgs,
  name,
  uid ? 1000,
  gid ? 1000,
  home ? "/home/${name}",
  shell ? "/bin/bash",
}:

let
  uidStr = toString uid;
  gidStr = toString gid;
in
pkgs.runCommand "mk-user-${name}" { } ''
  mkdir -p $out/etc/pam.d $out${home}

  # passwd: name:x:uid:gid:gecos:home:shell
  cat > $out/etc/passwd <<EOF
  root:x:0:0:root:/root:/bin/bash
  ${name}:x:${uidStr}:${gidStr}::${home}:${shell}
  EOF

  # shadow: name:!x:::::::
  cat > $out/etc/shadow <<EOF
  root:!x:::::::
  ${name}:!x:::::::
  EOF

  # group: name:x:gid:
  cat > $out/etc/group <<EOF
  root:x:0:
  ${name}:x:${gidStr}:
  EOF

  # gshadow
  cat > $out/etc/gshadow <<EOF
  root:x::
  ${name}:x::
  EOF

  # login.defs (required by some tools)
  touch $out/etc/login.defs
''
