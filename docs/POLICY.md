# Git Update Policy

The main purpose of this policy is to ensure that the `main` branch of this repo is always stable and verified *(post-Synthesis simulation verified)* and can be used to create a tapeout-ready design.

## 1. Branch Usage Rules
All new updates that are still under development and are not yet finalized, tested, and error-free shall be done in sub-branches.

Do not commit in-progress or unverified updates directly to the main integration branch.

## 2. Sub-Branch Naming Convention
If updates are being developed and tested by one individual, the branch name must follow this format:

`<first letter of first name>-<full last name>`

Example:
- For Rakesh Patil, the branch name should be `r-patil`.

Use lowercase letters and a single hyphen separator.

If people are working in teams together on a new feature, the branch name must be based on the feature name.

Format requirements for team feature branches:
- All lowercase letters
- Hyphens between words
- No spaces

Example:
- `flash-loader-handshake-improvement`

This is a typical branch view where working branches are ahead of `main`:

```text
main                                  o---o---o
r-patil                               o---o---o---o
flash-loader-handshake-improvement    o---o---o---o---o
									  ^ branches are ahead of main
```


```text
main
├── r-patil (ahead of main)
└── flash-loader-handshake-improvement (ahead of main)
```

## 3. Merge Readiness
A sub-branch is ready to merge only when:
- The update is finalized.
- Required testing is completed.
- Known errors are resolved.
- Coding style guidelines are followed.

## 4. Recommended Workflow
1. Create a sub-branch using the naming format above.
2. Implement and test updates in that branch.
3. Fix all identified errors.
4. Open a review/merge request only after the branch is stable and verified.

