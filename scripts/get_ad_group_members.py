#!/usr/bin/env python3
"""
get_ad_group_members.py

Terraform external data source — reads AD group membership via LDAPS.
Returns member UPNs as comma-separated JSON.

Input  (stdin): {"server":"...","username":"...","password":"...","group_name":"..."}
Output (stdout): {"upns":"user1@corp.com,user2@corp.com"}

Requirements on Terraform runner:
  /opt/homebrew/bin/python3 with ldap3 and pycryptodome installed:
    /opt/homebrew/bin/python3 -m pip install ldap3 pycryptodome --break-system-packages
"""

import json
import sys
import ssl

try:
    import ldap3
except ImportError:
    print(json.dumps({"error": "ldap3 not installed. Run: /opt/homebrew/bin/python3 -m pip install ldap3 pycryptodome --break-system-packages"}), file=sys.stderr)
    sys.exit(1)

def main():
    query = json.load(sys.stdin)
    server_host = query["server"]
    username    = query["username"]
    password    = query["password"]
    group_name  = query["group_name"]

    # ldap3 NTLM requires DOMAIN\username format.
    # Convert UPN (user@domain.com) to DOMAIN\user if needed.
    if "\\" not in username and "@" in username:
        user_part, domain_part = username.split("@", 1)
        ntlm_domain = domain_part.split(".")[0].upper()
        ntlm_user = f"{ntlm_domain}\\{user_part}"
    else:
        ntlm_user = username

    tls = ldap3.Tls(validate=ssl.CERT_NONE)
    server = ldap3.Server(server_host, port=636, use_ssl=True, tls=tls, get_info=ldap3.ALL)

    conn = ldap3.Connection(
        server,
        user=ntlm_user,
        password=password,
        authentication=ldap3.NTLM,
        auto_bind=True
    )

    # Derive naming context from server info
    nc = server.info.other.get("defaultNamingContext", [""])[0]
    if not nc:
        print(json.dumps({"error": "Could not determine defaultNamingContext"}), file=sys.stderr)
        sys.exit(1)

    # Find the group DN
    conn.search(nc, f"(sAMAccountName={group_name})", attributes=["distinguishedName"])
    if not conn.entries:
        print(json.dumps({"error": f"Group '{group_name}' not found in {nc}"}), file=sys.stderr)
        sys.exit(1)

    group_dn = conn.entries[0].distinguishedName.value

    # Get all members recursively using LDAP_MATCHING_RULE_IN_CHAIN (1.2.840.113556.1.4.1941)
    conn.search(
        nc,
        f"(&(objectClass=user)(memberOf:1.2.840.113556.1.4.1941:={group_dn}))",
        attributes=["userPrincipalName"]
    )

    upns = [
        str(entry.userPrincipalName)
        for entry in conn.entries
        if entry.userPrincipalName and str(entry.userPrincipalName) != ""
    ]

    conn.unbind()

    print(json.dumps({"upns": ",".join(upns)}))

if __name__ == "__main__":
    main()
