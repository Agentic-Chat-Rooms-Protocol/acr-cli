/*
 * Agentic Chat Room (ACR) Protocol - High Performance Cryptographic Invariants
 * Copyright (c) 2026 ACR Engineering Group. All rights reserved.
 * Licensed under the Apache License, Version 2.0.
 */

#ifndef ACR_CRYPTO_H_
#define ACR_CRYPTO_H_

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Validates whether an event state transition satisfies ACR hash-chain invariants.
 * Returns 1 if valid, 0 if invalid or corrupted.
 */
int acr_verify_state_hash(const char* prev_hash, const char* event_payload, const char* expected_hash);

/**
 * Checks whether an AST Diff payload preserves AST safety invariants.
 * Returns 1 if compliant, 0 if disallowed nodes detected.
 */
int acr_verify_ast_diff_invariants(const char* ast_diff_json);

/**
 * Computes whether a token bucket with capacity and refill rate permits cost deduction.
 * Returns remaining tokens if permitted, or -1 if rate limit exceeded.
 */
int acr_evaluate_rate_limit(int current_tokens, int max_capacity, int cost);

#ifdef __cplusplus
}
#endif

#endif /* ACR_CRYPTO_H_ */
