# SportsOS Game-Day Control Safety Acceptance

Milestone 15 closes the server-authoritative safety and permission layer around physical scoreboard controls.

## 15.1 Physical-control enable / lockout policy

- Server owns physical-control policy state.
- GAME, DEVICE, and GAME_DEVICE scopes are supported.
- ENABLED and LOCKED modes are supported.
- Locked controls are rejected before authoritative game mutation.
- Dashboard/localStorage state is not authority.

## 15.2 Operator lockout controls

- Operators can view active policies.
- Operators can enable or lock supported scopes.
- Operators can include a reason.
- Operators can remove explicit policies.
- UI writes only through the server policy API.

## 15.3 Game lifecycle auto-lock

- Physical controls are automatically constrained by authoritative game lifecycle.
- Active lifecycle states may accept controls.
- Final/completed/cancelled/postponed states are locked.
- Lifecycle is checked before authoritative mutation.
- Ambiguous lifecycle fails closed when an authoritative lifecycle route exists.

## 15.4 Role / permission enforcement

- Policy read and write permissions are distinct.
- Elevated operator roles are required for policy mutation.
- Device-originated controls remain authenticated as VERIFIED devices rather than human users.
- Role authority is not accepted from arbitrary request headers.

## 15.5 Policy-change audit / actor attribution

Policy changes record:

- actor user ID
- actor roles
- action
- prior policy
- next policy
- operator reason
- timestamp

## 15.6 Emergency physical-control kill switch

- A global emergency lock can immediately block physical mutations.
- Activation requires a reason.
- The lock is persistent and server-authoritative.
- Activation/clear operations require permission.
- Lock state is checked before authoritative execution.
- Rejected controls receive HTTP 423 while the emergency lock is active.

## 15.7 Health / safety status

The operator surface exposes:

- SAFE
- RESTRICTED
- EMERGENCY_LOCKED
- global physical-input availability
- number of locked policy scopes
- emergency-lock state

## 15.8 Incident / rejection timeline

Rejected or failed physical-control attempts surface:

- device ID
- game ID
- input ID
- input type
- sequence
- disposition
- error/rejection reason
- timestamp

## 15.9 Incident acknowledgement / resolution

- Incidents support OPEN, ACKNOWLEDGED, and RESOLVED states.
- Incident updates are actor-attributed.
- Resolving requires a note.
- Incident changes require elevated write permission.
- Operator UI exposes acknowledge and resolve actions.

## Final Milestone 15 gate

Run:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash scripts/run-game-day-control-safety-acceptance.sh
docker compose up -d --build api dashboard
npm run test:e2e:docker
```

Milestone 15 is complete when all commands are green.
