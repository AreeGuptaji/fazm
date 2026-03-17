#!/bin/bash
# Toggle session recording for specific users via PostHog feature flag.
#
# Usage:
#   ./scripts/session-recording-toggle.sh enable <email-or-uid>
#   ./scripts/session-recording-toggle.sh disable <email-or-uid>
#   ./scripts/session-recording-toggle.sh disable-all
#   ./scripts/session-recording-toggle.sh list
#   ./scripts/session-recording-toggle.sh check <email-or-uid>
#
# Accepts email (resolved to Firebase UID via PostHog) or Firebase UID directly.
# The flag targets Firebase UIDs (the distinct_id the app uses after sign-in).
# The flag is OFF by default. Changes take effect on next app launch (or within 5 min).

set -euo pipefail

PROJECT_ID="331630"
FLAG_ID="606686"
API_URL="https://us.posthog.com/api"
PROJECT_TOKEN="phc_TWwTa7D5GcjE4PprY55tJVfPKBC7kmLGiFUDZxBbYRQ"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
    set -a; source "$SCRIPT_DIR/../.env"; set +a
fi

if [ -z "${POSTHOG_PERSONAL_API_KEY:-}" ]; then
    echo "Error: POSTHOG_PERSONAL_API_KEY not set in .env"
    exit 1
fi

KEY="$POSTHOG_PERSONAL_API_KEY"

# Look up a person by email or UID and return all their distinct_ids + email.
# Output: JSON object {"firebase_uid": "...", "email": "...", "all_ids": [...]}
lookup_person() {
    local input="$1"
    curl -s "$API_URL/projects/$PROJECT_ID/persons/?search=$input" \
        -H "Authorization: Bearer $KEY" | python3 -c "
import json, sys

d = json.load(sys.stdin)
for person in d.get('results', []):
    ids = person.get('distinct_ids', [])
    props = person.get('properties', {})
    email = props.get('\$email', props.get('email', ''))

    # Find the Firebase UID: 20-30 char alphanumeric, no hyphens (not a UUID)
    firebase_uid = ''
    for did in ids:
        if 20 < len(did) < 36 and '-' not in did:
            firebase_uid = did
            break

    print(json.dumps({
        'firebase_uid': firebase_uid or (ids[0] if ids else ''),
        'email': email,
        'all_ids': ids
    }))
    sys.exit(0)

print(json.dumps({'firebase_uid': '', 'email': '', 'all_ids': []}))
"
}

# Resolve input (email or UID) to Firebase UID. Prints UID and email to stderr for display.
resolve_id() {
    local input="$1"
    local person_json
    person_json=$(lookup_person "$input")

    local firebase_uid email
    firebase_uid=$(echo "$person_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['firebase_uid'])")
    email=$(echo "$person_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['email'])")

    if [ -z "$firebase_uid" ]; then
        echo "Error: Could not find user '$input' in PostHog" >&2
        exit 1
    fi

    if [ -n "$email" ]; then
        echo "  User: $email (Firebase UID: $firebase_uid)" >&2
    else
        echo "  Firebase UID: $firebase_uid" >&2
    fi
    echo "$firebase_uid"
}

# Get all Firebase UIDs currently on the allowlist (excluding placeholder).
get_current_ids() {
    curl -s "$API_URL/projects/$PROJECT_ID/feature_flags/$FLAG_ID/" \
        -H "Authorization: Bearer $KEY" | python3 -c "
import json, sys
d = json.load(sys.stdin)
groups = d.get('filters', {}).get('groups', [])
if groups:
    props = groups[0].get('properties', [])
    for p in props:
        if p.get('key') == 'distinct_id':
            vals = p.get('value', [])
            if isinstance(vals, list):
                for v in vals:
                    if v != 'test-device-placeholder':
                        print(v)
"
}

# Reverse-resolve a Firebase UID to email via PostHog People API.
resolve_uid_to_email() {
    local uid="$1"
    curl -s "$API_URL/projects/$PROJECT_ID/persons/?search=$uid" \
        -H "Authorization: Bearer $KEY" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for person in d.get('results', []):
    ids = person.get('distinct_ids', [])
    if '$uid' in ids:
        props = person.get('properties', {})
        email = props.get('\$email', props.get('email', ''))
        print(email or '(no email)')
        sys.exit(0)
print('(unknown)')
"
}

update_ids() {
    local ids_json="$1"
    curl -s -X PATCH "$API_URL/projects/$PROJECT_ID/feature_flags/$FLAG_ID/" \
        -H "Authorization: Bearer $KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"filters\": {
                \"groups\": [{
                    \"properties\": [{
                        \"key\": \"distinct_id\",
                        \"value\": $ids_json,
                        \"operator\": \"exact\",
                        \"type\": \"person\"
                    }],
                    \"rollout_percentage\": 100
                }]
            }
        }" > /dev/null
}

# Check if ANY of a person's distinct_ids are on the allowlist.
check_person_on_allowlist() {
    local input="$1"
    local person_json
    person_json=$(lookup_person "$input")

    local email firebase_uid
    email=$(echo "$person_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['email'])")
    firebase_uid=$(echo "$person_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['firebase_uid'])")

    if [ -z "$firebase_uid" ]; then
        echo "Error: Could not find user '$input' in PostHog" >&2
        exit 1
    fi

    local display_name="$firebase_uid"
    [ -n "$email" ] && display_name="$email ($firebase_uid)"

    # Get all distinct_ids for this person
    local all_ids
    all_ids=$(echo "$person_json" | python3 -c "
import json, sys
for did in json.load(sys.stdin)['all_ids']:
    print(did)
")

    # Get current allowlist
    local current
    current=$(get_current_ids)

    # Check if any of person's IDs are on the allowlist
    local found_id=""
    while IFS= read -r did; do
        if echo "$current" | grep -qx "$did"; then
            found_id="$did"
            break
        fi
    done <<< "$all_ids"

    if [ -n "$found_id" ]; then
        echo "Recording: ENABLED for $display_name"
        if [ "$found_id" != "$firebase_uid" ]; then
            echo "  (matched via distinct_id: $found_id)"
        fi
    else
        echo "Recording: DISABLED for $display_name"
    fi
}

usage() {
    echo "Usage: $0 {enable|disable|disable-all|list|check} [email-or-uid]"
    echo ""
    echo "  enable <email-or-uid>    Start recording for this user"
    echo "  disable <email-or-uid>   Stop recording for this user"
    echo "  disable-all              Stop recording for ALL users"
    echo "  list                     Show all users with recording enabled"
    echo "  check <email-or-uid>     Check if recording is enabled for a user"
    echo ""
    echo "Accepts email (auto-resolves via PostHog) or Firebase UID directly."
    echo "The app identifies by Firebase UID after sign-in — that's what gets targeted."
    exit 1
}

[ $# -lt 1 ] && usage

CMD="$1"
INPUT="${2:-}"

case "$CMD" in
    enable)
        [ -z "$INPUT" ] && { echo "Error: email or uid required"; usage; }
        UID_VAL=$(resolve_id "$INPUT")
        CURRENT=$(get_current_ids)
        if echo "$CURRENT" | grep -qx "$UID_VAL"; then
            echo "Already enabled."
            exit 0
        fi
        ALL_IDS=$(echo -e "$CURRENT\n$UID_VAL" | grep -v '^$' | sort -u)
        IDS_JSON=$(echo "$ALL_IDS" | python3 -c "import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))")
        update_ids "$IDS_JSON"
        echo "✓ Recording enabled (takes effect within 5 min or on next app launch)"
        ;;
    disable)
        [ -z "$INPUT" ] && { echo "Error: email or uid required"; usage; }
        UID_VAL=$(resolve_id "$INPUT")
        CURRENT=$(get_current_ids)
        # Remove ALL distinct_ids for this person from the allowlist (not just the Firebase UID)
        PERSON_JSON=$(lookup_person "$INPUT")
        ALL_PERSON_IDS=$(echo "$PERSON_JSON" | python3 -c "
import json, sys
for did in json.load(sys.stdin)['all_ids']:
    print(did)
")
        REMAINING=$(echo "$CURRENT" | while IFS= read -r id; do
            if ! echo "$ALL_PERSON_IDS" | grep -qx "$id"; then
                echo "$id"
            fi
        done || true)
        REMAINING=$(echo "$REMAINING" | grep -v '^$' || true)
        if [ -z "$REMAINING" ]; then
            IDS_JSON='["test-device-placeholder"]'
        else
            IDS_JSON=$(echo "$REMAINING" | python3 -c "import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))")
        fi
        update_ids "$IDS_JSON"
        echo "✓ Recording disabled (takes effect within 5 min or on next app launch)"
        ;;
    disable-all)
        update_ids '["test-device-placeholder"]'
        echo "✓ Recording disabled for ALL users"
        ;;
    list)
        CURRENT=$(get_current_ids)
        if [ -z "$CURRENT" ]; then
            echo "No users with session recording enabled."
            exit 0
        fi
        COUNT=$(echo "$CURRENT" | wc -l | tr -d ' ')
        echo "Users with session recording enabled ($COUNT):"
        echo ""
        while IFS= read -r uid; do
            email=$(resolve_uid_to_email "$uid")
            printf "  %-30s %s\n" "$uid" "$email"
        done <<< "$CURRENT"
        ;;
    check)
        [ -z "$INPUT" ] && { echo "Error: email or uid required"; usage; }
        check_person_on_allowlist "$INPUT"
        ;;
    *)
        usage
        ;;
esac
