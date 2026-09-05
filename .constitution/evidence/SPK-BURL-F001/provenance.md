# SPK-BURL-F001 historical provenance

The evidence was first produced in commit
`e0cbdb885d846115ffcc1a63691df7f861d1204c` at
`.constitution/evidence/edit-f001/`. That commit contains the following
exact bytes:

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `README.md` | 1,945 | `baeb1c73c7459877737b417bed634fc84767059e34c893243060cbd07f824b15` |
| `formatted.png` | 703,167 | `7f7360672ab2c6115561066e3236da92465c031d3bc0b1e47c680256cbba3e9c` |
| `heading-focused.png` | 703,492 | `04bf895ecaf5bd199b45fbceecb4aee3cf90435005fb838b38f0d69df006d604` |
| `list-focused.png` | 695,669 | `ae437258755e44f47b5cc2d1e20ed01a747ef9d4d93e0fd64659fb7a83857433` |
| `paragraph-focused.png` | 703,760 | `df73bdd6093ffa46200ee8cb5aa58da630553ee8ff01f4c68c3212b3f5227e17` |

Commit `f7e447f5544e5595a858ba99d9cc1da384fd5d9d` migrated the evidence to
`.constitution/evidence/SPK-BURL-F001/`. It normalized the README from the
`EDIT-F001` name to `BURL-F001`: 1,961 bytes with SHA-256
`2800128c6c740072269dcd9a3da71b6404a35f6f9a863e85b8e34b9ae7c90a93`.
Each PNG keeps the same Git blob object and, therefore, the exact bytes and
SHA-256 value recorded above.

## Reproduce the record

Run these commands from the repository root. Both commit IDs are immutable.

```sh
ORIGINAL_COMMIT=e0cbdb885d846115ffcc1a63691df7f861d1204c
MIGRATION_COMMIT=f7e447f5544e5595a858ba99d9cc1da384fd5d9d
MIGRATION_README=.constitution/evidence/SPK-BURL-F001/README.md

git ls-tree -r "$ORIGINAL_COMMIT" -- .constitution/evidence/edit-f001
git ls-tree -r "$MIGRATION_COMMIT" -- .constitution/evidence/SPK-BURL-F001

for FILE in README.md \
  formatted.png \
  heading-focused.png \
  list-focused.png \
  paragraph-focused.png
do
  git cat-file -s "$ORIGINAL_COMMIT:.constitution/evidence/edit-f001/$FILE"
  git show "$ORIGINAL_COMMIT:.constitution/evidence/edit-f001/$FILE" | sha256sum
done

for FILE in formatted.png \
  heading-focused.png \
  list-focused.png \
  paragraph-focused.png
do
  ORIGINAL_BLOB=$(git rev-parse \
    "$ORIGINAL_COMMIT:.constitution/evidence/edit-f001/$FILE")
  MIGRATION_BLOB=$(git rev-parse \
    "$MIGRATION_COMMIT:.constitution/evidence/SPK-BURL-F001/$FILE")
  test "$ORIGINAL_BLOB" = "$MIGRATION_BLOB"
  printf '%s %s\n' "$FILE" "$ORIGINAL_BLOB"
done

git cat-file -s "$MIGRATION_COMMIT:$MIGRATION_README"
git show "$MIGRATION_COMMIT:$MIGRATION_README" | sha256sum
```
