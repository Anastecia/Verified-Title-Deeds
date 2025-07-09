;; verified-title-deeds.clar
;; This contract manages real estate titles as NFTs with a legal verification layer.

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED u101)
(define-constant ERR_OWNER_ONLY u102)
(define-constant ERR_TOKEN_NOT_FOUND u103)
(define-constant ERR_METADATA_FROZEN u104)
(define-constant ERR_TRANSFER_NOT_VERIFIED u105)
(define-constant ERR_ALREADY_VERIFIED u106)
(define-constant ERR_VERIFIER_ONLY u107)
(define-constant ERR_INVALID_RECIPIENT u108)
(define-constant ERR_SENDER_IS_RECIPIENT u109)
(define-constant ERR_INVALID_PROPERTY_ID u110)

;; Data Storage
(define-data-var last-token-id uint u0)
(define-data-var legal-verifier principal tx-sender)

;; NFT Definition
(define-non-fungible-token title-deed uint)

;; --- Data Maps ---
;; Maps token ID to a tuple of property metadata.
(define-map property-metadata uint {
    property-id: (string-ascii 64),
    legal-description: (string-utf8 256),
    jurisdiction: (string-ascii 64),
    metadata-frozen: bool
})

;; Maps a potential transfer (identified by token-id) to its verification status.
(define-map transfer-verifications uint {
    verified: bool,
    new-owner: principal
})

;; --- Administrative Functions ---

;; @desc Sets the principal responsible for verifying transfers.
;; @param new-verifier: The principal of the new legal verifier.
;; @returns (response bool)
(define-public (set-legal-verifier (new-verifier principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) (err ERR_OWNER_ONLY))
        (var-set legal-verifier new-verifier)
        (ok true)
    )
)

;; @desc Mints a new title deed NFT for a property.
;; @param recipient: The initial owner of the title.
;; @param property-id: A unique identifier for the property (e.g., parcel number).
;; @param legal-desc: The legal description of the property.
;; @param juris: The jurisdiction (e.g., "City of Metropolis").
;; @returns (response uint) The ID of the newly minted token.
(define-public (mint (recipient principal) (property-id (string-ascii 64)) (legal-desc (string-utf8 256)) (juris (string-ascii 64)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) (err ERR_OWNER_ONLY))
        (asserts! (> (len property-id) u0) (err ERR_INVALID_PROPERTY_ID))

        (let ((token-id (+ (var-get last-token-id) u1)))
            (try! (nft-mint? title-deed token-id recipient))
            (map-set property-metadata token-id {
                property-id: property-id,
                legal-description: legal-desc,
                jurisdiction: juris,
                metadata-frozen: false
            })
            (var-set last-token-id token-id)
            (print { type: "mint", token-id: token-id, owner: recipient })
            (ok token-id)
        )
    )
)

;; @desc Updates the legal description for a property. Can only be done before metadata is frozen.
;; @param token-id: The ID of the title deed NFT.
;; @param new-desc: The new legal description.
;; @returns (response bool)
(define-public (update-legal-description (token-id uint) (new-desc (string-utf8 256)))
    (begin
        (asserts! (is-eq tx-sender (unwrap! (nft-get-owner? title-deed token-id) (err ERR_TOKEN_NOT_FOUND))) (err ERR_NOT_AUTHORIZED))
        (let ((metadata (unwrap! (map-get? property-metadata token-id) (err ERR_TOKEN_NOT_FOUND))))
            (asserts! (not (get metadata-frozen metadata)) (err ERR_METADATA_FROZEN))
            (map-set property-metadata token-id (merge metadata { legal-description: new-desc }))
            (ok true)
        )
    )
)

;; @desc Freezes the metadata for a property, preventing future updates.
;; @param token-id: The ID of the title deed NFT.
;; @returns (response bool)
(define-public (freeze-metadata (token-id uint))
    (begin
        (asserts! (is-eq tx-sender (unwrap! (nft-get-owner? title-deed token-id) (err ERR_TOKEN_NOT_FOUND))) (err ERR_NOT_AUTHORIZED))
        (let ((metadata (unwrap! (map-get? property-metadata token-id) (err ERR_TOKEN_NOT_FOUND))))
            (asserts! (not (get metadata-frozen metadata)) (err ERR_METADATA_FROZEN))
            (map-set property-metadata token-id (merge metadata { metadata-frozen: true }))
            (ok true)
        )
    )
)

;; --- Transfer Logic ---

;; @desc The legal verifier approves a transfer to a new owner.
;; @param token-id: The ID of the token being transferred.
;; @param new-owner: The principal of the intended recipient.
;; @returns (response bool)
(define-public (approve-transfer (token-id uint) (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get legal-verifier)) (err ERR_VERIFIER_ONLY))
        (asserts! (is-some (map-get? property-metadata token-id)) (err ERR_TOKEN_NOT_FOUND))
        (map-set transfer-verifications token-id { verified: true, new-owner: new-owner })
        (print { type: "transfer-approval", token-id: token-id, approved-for: new-owner })
        (ok true)
    )
)

;; @desc Transfers the title deed NFT to a new owner. Requires prior approval.
;; @param token-id: The ID of the token to transfer.
;; @param sender: The current owner of the NFT.
;; @param recipient: The new owner of the NFT.
;; @returns (response bool)
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
    (begin
        (asserts! (is-eq tx-sender sender) (err ERR_NOT_AUTHORIZED))
        (asserts! (not (is-eq sender recipient)) (err ERR_SENDER_IS_RECIPIENT))

        (let ((verification (unwrap! (map-get? transfer-verifications token-id) (err ERR_TRANSFER_NOT_VERIFIED))))
            ;; Check if the transfer is verified and for the correct recipient
            (asserts! (get verified verification) (err ERR_TRANSFER_NOT_VERIFIED))
            (asserts! (is-eq (get new-owner verification) recipient) (err ERR_INVALID_RECIPIENT))

            ;; Reset verification status after use
            (map-set transfer-verifications token-id { verified: false, new-owner: recipient })

            (try! (nft-transfer? title-deed token-id sender recipient))
            (print { type: "transfer", token-id: token-id, from: sender, to: recipient })
            (ok true)
        )
    )
)

;; @desc Emergency transfer by contract owner, bypassing verification. For recovery.
;; @param token-id: The ID of the token to transfer.
;; @param current-owner: The principal of the current owner.
;; @param new-owner: The principal of the new owner.
;; @returns (response bool)
(define-public (emergency-transfer (token-id uint) (current-owner principal) (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) (err ERR_OWNER_ONLY))
        (try! (nft-transfer? title-deed token-id current-owner new-owner))
        (print { type: "emergency-transfer", token-id: token-id, from: current-owner, to: new-owner })
        (ok true)
    )
)

;; --- Read-Only Functions ---

;; @desc Gets the owner of a specific title deed NFT.
;; @param token-id: The ID of the token.
;; @returns (response (optional principal)) The owner's principal.
(define-read-only (get-owner (token-id uint))
    (ok (nft-get-owner? title-deed token-id))
)

;; @desc Gets the metadata for a specific property.
;; @param token-id: The ID of the token.
;; @returns (optional (tuple ...)) The property metadata.
(define-read-only (get-property-metadata (token-id uint))
    (map-get? property-metadata token-id)
)

;; @desc Gets the current legal verifier principal.
;; @returns (response principal)
(define-read-only (get-legal-verifier)
    (ok (var-get legal-verifier))
)

;; @desc Gets the last token ID that was minted.
;; @returns (response uint)
(define-read-only (get-last-token-id)
    (ok (var-get last-token-id))
)

;; @desc Checks the verification status of a pending transfer.
;; @param token-id: The ID of the token.
;; @returns (optional (tuple ...)) The verification status.
(define-read-only (get-transfer-verification-status (token-id uint))
    (map-get? transfer-verifications token-id)
)