@{
    # This policy contains only user-approved suggestions. The accompanying
    # proposal command is read-only and does not apply any listed action.
    Version = 2

    NewsletterSenders = @(
        'myFT',
        'FirstFT',
        'FT Energy Source',
        'Eater'
    )

    GitHubSecurityPatterns = @(
        '(?i)\b(oauth .* (added|application)|please review this sign[ -]?in|security alert|verification code|password)\b'
    )
    GitHubActionPatterns = @(
        '(?i)\b(build|deploy(ment)?|workflow|action required|failed|failure|error)\b'
    )

    RevolutAccountPatterns = @(
        '(?i)\b(card|payment|charge|cash withdrawal|transfer|statement|fee|account|security|verification)\b'
    )
    RevolutPromotionPatterns = @(
        '(?i)\b(revpoints|gift a plan|inspired by crypto|offer|save|discount)\b'
    )

    ProtectedPatterns = @{
        'Health, government, legal, or debt' = '(?i)\b(digital post|hospital|psykiatri|health|debt|inkasso|final notice|overdue|legal|court|tax|skat)\b'
        'Invoice, payment, or receipt' = '(?i)\b(invoice|faktura|receipt|order receipt|payment|betaling)\b'
        'Delivery or booking' = '(?i)\b(delivered|dispatched|parcel|package|pakke|hente pakke|booking)\b'
        'Mail from a person or work contact' = '(?i)\b(meeting|calendar|interview|upload cv|application|job|møde)\b'
    }
}
