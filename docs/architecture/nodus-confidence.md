# Nodus confidence and freshness

Confidence is a product subsystem outside the generated answer. Nodus is never asked for a percentage and trusted at face value. `NodusConfidenceEngine` combines deterministic signals such as question domain, freshness class, evidence availability, domain evaluation performance, structured-output validity, termination state, and explicit uncertainty.

The internal envelope separates:

- answer confidence: whether the proposed answer is likely correct;
- evidence confidence: how much reliable local evidence supports it;
- freshness confidence: whether locally available knowledge is adequate for the time sensitivity.

Internal scores are clamped numeric values for evaluation and calibration. The UI presents `High`, `Medium`, `Low`, or `Needs verification`, avoiding false precision. Freshness is separately classified as `stable`, `possibly_stale`, `current_data_required`, or `unknown`.

Freshness can override a superficially plausible answer. Requests containing current, latest, today, yesterday, live price, weather, election, office-holder, release, or similar time-sensitive intent are treated conservatively. A current-data question may receive stable background context, but cannot receive a fake high-confidence current answer.

Verification is recommended for current-data requirements, low confidence, contradictory evidence, unknown domains, or high-risk factual claims. Abstention—“I don't have enough reliable local information”—is a valid successful outcome.

Held-out results calibrate predicted confidence against correctness by domain. Reports include reliability buckets, calibration error, overconfidence, and underconfidence. Promotion requires calibration not to regress, appropriate verification recommendations, safe freshness behavior, and appropriate abstention; aggregate accuracy alone is insufficient.
