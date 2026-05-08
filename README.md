# Certificate_Validation_Script


1.  **Overall program logic (theory / intent)**
2.  **High‑level flow chart (textual)**
3.  **Modules / functions / loops used**
4.  **Block‑by‑block explanation**
5.  **Line‑by‑line explanation with commands and syntax**
6.  **Fully rewritten script with detailed comments on every line**

***

## 1️⃣ Program Logic – Theory (What this script is designed to do)

This script is a **two‑phase automation** used in production support to:

### **Phase 1 – DNS → VIP Resolution**

*   Read a list of DNS names from an input file (`dnsllist.in`)
*   Resolve each DNS name to its **VIP (IP address)** using `nslookup`
*   Handle failures cleanly (`Not_Resolved`)
*   Generate a **clean, aligned report**:
        dns_vip_list.out
    Example:
        DNS_NAME           VIP_ADDRESS
        --------           -----------
        app1.example.com   10.20.30.40
        app2.example.com   Not_Resolved

### **Phase 2 – SSL Certificate Inspection**

For each DNS–VIP pair:

*   Connect to port **443**
*   Extract **certificate details** using OpenSSL:
    *   CN (Common Name)
    *   Signer (Issuer CN)
    *   Validity dates
*   Do this **twice**:
    *   **Default certificate** (with `-servername`, SNI-aware)
    *   **SNI certificate** (without `-servername`)
*   Write a structured output:
        OpenSSL.out

### **Key design goals**

✅ Sequential dependency (Phase‑2 runs only after Phase‑1)  
✅ Clean formatting for audit/KT  
✅ Defensive handling (blank lines, unresolved DNS, missing certs)  
✅ Reusable functions (modular design)

***

## 2️⃣ Flow Chart (Textual Representation)

    START
     |
     |-- Read INPUT_FILE (dnsllist.in)
     |    |
     |    |-- For each DNS
     |         |
     |         |-- If blank → skip
     |         |-- nslookup DNS
     |         |-- Extract last IP
     |         |-- If empty → Not_Resolved
     |         |-- Save DNS|VIP to temp file
     |
     |-- Calculate max DNS length
     |-- Format and write dns_vip_list.out
     |
     |-- Read dns_vip_list.out (skip headers)
     |    |
     |    |-- For each DNS + VIP
     |         |
     |         |-- If VIP = Not_Resolved
     |         |     → Write Not_Available cert output
     |         |
     |         |-- Else
     |               |
     |               |-- Fetch Default cert
     |               |-- Fetch SNI cert
     |               |-- Extract CN, Issuer CN, dates
     |
     |-- Write OpenSSL.out
     |
    END

***

## 3️⃣ Modules, Functions, Loops Used

### **Loops**

| Type             | Purpose                          |                       |
| ---------------- | -------------------------------- | --------------------- |
| `while read DNS` | Process each DNS from input file |                       |
| \`awk …          | while read DNS VIP\`             | Iterate DNS/VIP pairs |

### **Functions (Modules)**

| Function           | Purpose                             |
| ------------------ | ----------------------------------- |
| `extract_cn()`     | Extract CN from subject/issuer line |
| `get_cert_block()` | Fetch and format cert details       |

### **External Commands Used**

*   `nslookup`
*   `openssl s_client`
*   `openssl x509`
*   `awk`
*   `printf`
*   `tail`
*   `rm`

***

## 4️⃣ Block‑by‑Block Explanation

### **Block 1: Variable Initialization**

Defines input, output, and temp files.
Uses `$$` (PID) to avoid temp file collision.

***

### **Block 2: DNS → VIP Resolution**

*   Reads DNS names
*   Skips blank lines
*   Uses `nslookup`
*   Extracts last `Address:` (most reliable VIP)
*   Writes raw output to temp file

***

### **Block 3: Output Formatting**

*   Calculates longest DNS length dynamically
*   Aligns columns using `printf` and `awk`
*   Produces professional report

***

### **Block 4: Certificate Helper Functions**

*   `extract_cn`: Handles **both** OpenSSL output styles:
    *   `CN = value`
    *   `/CN=value`
*   `get_cert_block`: Fetches:
    *   Subject CN
    *   Issuer CN
    *   notBefore / notAfter dates

***

### **Block 5: OpenSSL Processing**

*   Reads DNS/VIP pairs
*   Handles unresolved VIP separately
*   Executes:
    *   Default cert check
    *   SNI cert check
*   Writes structured output

***

## 5️⃣ Line‑by‑Line Explanation (Key Commands)

### **Shebang**

```ksh
#!/bin/ksh
```

→ Ensures KornShell is used (important for enterprise UNIX)

***

### **Temp file**

```ksh
TMP_FILE="/tmp/dns_vip_tmp.$$"
```

*   `$$` = current process ID
*   Prevents overwrite by parallel runs

***

### **While loop**

```ksh
while read DNS
```

*   Reads input **line by line**
*   Safer than `for` for DNS names

***

### **Blank line skip**

```ksh
[ -z "$DNS" ] && continue
```

*   `-z` checks empty string
*   `continue` skips loop iteration

***

### **nslookup logic**

```ksh
nslookup "$DNS" 2>/dev/null | awk '/^Address: / {print $2}' | tail -1
```

Breakdown:

*   `2>/dev/null` → suppress errors
*   `awk` → extracts IP address
*   `tail -1` → picks final resolved VIP

***

### **OpenSSL Default cert**

```ksh
openssl s_client -servername "$DNS" -connect "${VIP}:443"
```

*   `-servername` → forces SNI behavior
*   Ensures correct cert for multi‑host VIP

***

### **OpenSSL SNI cert**

```ksh
openssl s_client -connect "${VIP}:443"
```

*   No `-servername`
*   Returns default backend cert

***

### **extract\_cn()**

Uses `awk match()` and regex to support **both formats**:

*   `CN = example.com`
*   `/CN=example.com`

***

## 6️⃣ Rewritten Script – Fully Commented (Every Line Explained)

```ksh
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
```

***

If you want, next I can:

*   ✅ Convert this into **KT documentation**
*   ✅ Draw a **visual flowchart (ASCII or diagram-ready)**
*   ✅ Optimize for **large DNS lists**
*   ✅ Convert to **bash‑compatible version**

Just tell me 👍
