# Test photos for CWSB Check

Photos that the v1 model never saw: none of them is in v1's training, validation
or test set.

| Folder | Photos | True label | Where they come from |
|---|---|---|---|
| `unhealthy_infested_closeups/` | 211 | Unhealthy | The infested stem close-ups that were added for v2 (`images_health_16_11_v2`). 47 source photos, each in several cropped or rotated versions. |
| `healthy_closeups/` | 19 | Healthy | Close-ups of healthy plants (`test_new`, duplicates removed). These were not used by v1 or v2. |

## How "not used by v1" was checked

- Byte-for-byte comparison against all 498 photos v1 was built from, and against
  the `test/` and `test2/` sets: no match.
- Appearance comparison (including mirrored and centre-cropped versions) against
  the same 498 photos: no near-copy. The closest pairs are clearly different pictures.

The photos carry no plant numbers, so this shows they are different photographs.
It cannot show that they are different plants.

## What the app says about them

`results.csv` holds the app's answer for every photo (run on 25 Nov 2026).

| True label | App says Healthy | App says Unsure | App says Unhealthy |
|---|---|---|---|
| Unhealthy (211) | 4 | 5 | 202 |
| Healthy (19) | 0 | 0 | 19 |

The app calls every healthy close-up Unhealthy. This is the known weakness of
v1: it was trained on whole-plant photos with only 9 healthy plants and no
healthy close-ups. Expect it when you test with this folder.

To repeat the run: start the server, then `python backend/run_test_dataset.py`.
