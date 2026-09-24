# Nodus model lifecycle

Model execution and model trust are separate axes. Availability answers whether an artifact can execute on this device. Lifecycle stage answers whether that exact artifact is suitable for evaluation or shipping.

- `experimentalCandidate`: hash-pinned and runnable in developer-only surfaces; production shipping is forbidden.
- `candidate`: has passed the required technical evaluation but still awaits explicit acceptance.
- `accepted`: passed every production gate and explicit review; eligible for normal packaging under release policy.
- `quarantined`: rejected from execution because integrity, safety, provenance, or post-acceptance evidence is unacceptable.

Nodus R7 Experimental is `experimentalCandidate` and has `shippingAllowed = false`. Debug builds may include it from the verified local developer cache. Release and archive builds omit it by default. An explicit Release override is for developer testing only and does not change lifecycle metadata.

The intended flow is:

`train → fast diagnostic evaluation → experimentalCandidate → Developer Nodus Chat → local human evaluation → full promotion suite → candidate → explicit review → accepted`

At every transition, hashes and provenance remain bound to the artifact. Model output, prompts, ratings, and build flags cannot forge a lifecycle stage or authorize promotion.
