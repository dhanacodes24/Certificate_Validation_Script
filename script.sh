#!/bin/ksh
# ==========================================================
# Script Name : dns_vip_openssl_check.ksh
# Purpose     : 
#   1) Resolve DNS names to VIPs
#   2) Extract SSL certificate details (Default & SNI)
# Author      : ---
# ==========================================================

# ---------- Input / Output files ----------
INPUT_FILE="dnsllist.in"             # Input file containing DNS names
DNSVIP_OUT="dns_vip_list.out"        # Output: DNS to VIP mapping
OPENSSL_OUT="OpenSSL.out"            # Output: Certificate details

# Temporary file with PID to avoid conflicts
TMP_FILE="/tmp/dns_vip_tmp.$$"

# ==========================================================
# PART 1: DNS → VIP Resolution
# ==========================================================

> "$TMP_FILE"                        # Truncate temp file

# Read DNS names line by line
while read DNS
do
    # Skip empty lines
    [ -z "$DNS" ] && continue

    # Resolve DNS to IP (VIP)
    VIP=$(nslookup "$DNS" 2>/dev/null \
          | awk '/^Address: / {print $2}' \
          | tail -1)

    # If resolution fails, mark explicitly
    [ -z "$VIP" ] && VIP="Not_Resolved"

    # Store raw DNS|VIP data
    echo "$DNS|$VIP" >> "$TMP_FILE"

done < "$INPUT_FILE"

# Determine max DNS length for aligned output
MAX_LEN=$(awk -F'|' '
{
  if (length($1) > max) max = length($1)
}
END { print max+0 }
' "$TMP_FILE")

# Write formatted header
printf "%-${MAX_LEN}s  %s\n" "DNS_NAME" "VIP_ADDRESS" > "$DNSVIP_OUT"
printf "%-${MAX_LEN}s  %s\n" "--------" "-----------" >> "$DNSVIP_OUT"

# Write formatted body
awk -F'|' -v len="$MAX_LEN" '
{
  printf "%-"len"s  %s\n", $1, $2
}
' "$TMP_FILE" >> "$DNSVIP_OUT"

# Remove temp file
rm -f "$TMP_FILE"

# ==========================================================
# PART 2: OpenSSL Certificate Inspection
# ==========================================================

> "$OPENSSL_OUT"                     # Truncate output file

# ---------- Function: Extract CN ----------
extract_cn()
{
    echo "$1" | awk '
    {
      if (match($0, /CN[[:space:]]*=[[:space:]]*[^,\/]+/)) {
        s=substr($0, RSTART, RLENGTH)
        sub(/CN[[:space:]]*=[[:space:]]*/, "", s)
        print s
        exit
      }
      if (match($0, /\/CN=[^\/,]+/)) {
        s=substr($0, RSTART, RLENGTH)
        sub(/\/CN=/, "", s)
        print s
        exit
      }
      print "Not_Available"
    }'
}

# ---------- Function: Fetch Certificate ----------
get_cert_block()
{
    CERTTYPE="$1"                    # Default or SNI
    DNS="$2"
    VIP="$3"

    if [ "$CERTTYPE" = "Default" ]; then
        RAW=$(echo | openssl s_client \
              -servername "$DNS" \
              -connect "${VIP}:443" 2>/dev/null \
              | openssl x509 -noout -subject -issuer -dates 2>/dev/null)
    else
        RAW=$(echo | openssl s_client \
              -connect "${VIP}:443" 2>/dev/null \
              | openssl x509 -noout -subject -issuer -dates 2>/dev/null)
    fi

    # If cert retrieval fails
    if [ -z "$RAW" ]; then
        echo "${CERTTYPE} cert CN=Not_Available"
        echo "signer CN=Not_Available"
        echo "Validity not before=Not_Available"
        echo "Validity not after=Not_Available"
        return
    fi

    # Extract fields
    SUBJECT_LINE=$(echo "$RAW" | awk '/^subject=/{print; exit}')
    ISSUER_LINE=$(echo "$RAW"  | awk '/^issuer=/{print; exit}')
    NOTBEFORE=$(echo "$RAW"    | awk -F= '/^notBefore=/{print $2; exit}')
    NOTAFTER=$(echo "$RAW"     | awk -F= '/^notAfter=/{print $2; exit}')

    CERT_CN=$(extract_cn "$SUBJECT_LINE")
    SIGNER_CN=$(extract_cn "$ISSUER_LINE")

    echo "${CERTTYPE} cert CN=${CERT_CN}"
    echo "signer CN=${SIGNER_CN}"
    echo "Validity not before=${NOTBEFORE}"
    echo "Validity not after=${NOTAFTER}"
}

# ---------- Main OpenSSL Loop ----------
awk 'NR>2 {print $1, $2}' "$DNSVIP_OUT" | while read DNS VIP
do
    [ -z "$DNS" ] && continue

    if [ "$VIP" = "Not_Resolved" ]; then
        echo "The Default cert for DNS \"$DNS\" and vip \"$VIP\" is as below" >> "$OPENSSL_OUT"
        echo "Default cert CN=Not_Available" >> "$OPENSSL_OUT"
        echo "signer CN=Not_Available" >> "$OPENSSL_OUT"
        echo "Validity not before=Not_Available" >> "$OPENSSL_OUT"
        echo "Validity not after=Not_Available" >> "$OPENSSL_OUT"
        echo "" >> "$OPENSSL_OUT"

        echo "The SNI cert for DNS \"$DNS\" and vip \"$VIP\" is as below" >> "$OPENSSL_OUT"
        echo "SNI cert CN=Not_Available" >> "$OPENSSL_OUT"
        echo "signer CN=Not_Available" >> "$OPENSSL_OUT"
        echo "Validity not before=Not_Available" >> "$OPENSSL_OUT"
        echo "Validity not after=Not_Available" >> "$OPENSSL_OUT"
        echo "*** **************************************" >> "$OPENSSL_OUT"
        echo "" >> "$OPENSSL_OUT"
        continue
    fi

    echo "The Default cert for DNS \"$DNS\" and vip \"$VIP\" is as below" >> "$OPENSSL_OUT"
    get_cert_block "Default" "$DNS" "$VIP" >> "$OPENSSL_OUT"
    echo "" >> "$OPENSSL_OUT"

    echo "The SNI cert for DNS \"$DNS\" and vip \"$VIP\" is as below" >> "$OPENSSL_OUT"
    get_cert_block "SNI" "$DNS" "$VIP" >> "$OPENSSL_OUT"

    echo "*** **************************************" >> "$OPENSSL_OUT"
    echo "" >> "$OPENSSL_OUT"
done

# Final confirmation
echo "Generated: $DNSVIP_OUT"
echo "Generated: $OPENSSL_OUT"
