"""Seed Stripe catalog for the Vinea Wine Club demo.

Creates one Product per wine bottle and a single one-time Price with a stable
lookup_key of the form ``wine_<wine.id>``. Idempotent: re-running only creates
missing entries.

Usage::

    python setup_stripe.py
"""
from __future__ import annotations

import os

import stripe
from dotenv import load_dotenv

load_dotenv()

stripe.api_key = os.environ["STRIPE_SECRET_KEY"]

# Physical goods tax code (generic tangible).
TAX_CODE_PHYSICAL = "txcd_99999999"

# Wine catalog mirrored from /app/frontend/src/data/wines.ts.
# Prices are in EUR cents (1 EUR = 100).
CATALOG = [
    {
        "id": "monfortino-2015",
        "name": "Giacomo Conterno — Barolo Riserva Monfortino 2015",
        "amount_cents": 118000,
    },
    {
        "id": "sassicaia-2018",
        "name": "Tenuta San Guido — Sassicaia 2018",
        "amount_cents": 26000,
    },
    {
        "id": "tignanello-2019",
        "name": "Antinori — Tignanello 2019",
        "amount_cents": 13500,
    },
    {
        "id": "dom-perignon-2013",
        "name": "Moët & Chandon — Dom Pérignon Vintage 2013",
        "amount_cents": 23000,
    },
    {
        "id": "ornellaia-2017",
        "name": "Ornellaia 2017",
        "amount_cents": 23500,
    },
    {
        "id": "biondi-santi-2016",
        "name": "Biondi-Santi — Brunello di Montalcino 2016",
        "amount_cents": 32000,
    },
    {
        "id": "rinaldi-brunate-2018",
        "name": "Giuseppe Rinaldi — Barolo Brunate 2018",
        "amount_cents": 48000,
    },
    {
        "id": "cadelbosco-annamaria-2015",
        "name": "Ca' del Bosco — Cuvée Annamaria Clementi 2015",
        "amount_cents": 17500,
    },
]

CURRENCY = "eur"


def get_or_create_product(entry: dict) -> stripe.Product:
    catalog_id = f"vinea_{entry['id']}"
    # Look up by stable, provider-independent Vinea metadata.
    for p in stripe.Product.list(active=True, limit=100).auto_paging_iter():
        if p.to_dict().get("metadata", {}).get("vinea_catalog_id") == catalog_id:
            return p
    return stripe.Product.create(
        name=entry["name"],
        tax_code=TAX_CODE_PHYSICAL,
        metadata={
            "managed_by": "vinea",
            "vinea_catalog_id": catalog_id,
            "wine_id": entry["id"],
        },
    )


def ensure_price(product_id: str, entry: dict) -> stripe.Price:
    lookup_key = f"wine_{entry['id']}"
    existing = stripe.Price.list(lookup_keys=[lookup_key], active=True, limit=1).data
    if existing:
        p = existing[0]
        if p.unit_amount == entry["amount_cents"] and p.currency == CURRENCY:
            return p
        # Deactivate stale price so lookup_key is free for the new one.
        stripe.Price.modify(p.id, active=False)

    return stripe.Price.create(
        product=product_id,
        unit_amount=entry["amount_cents"],
        currency=CURRENCY,
        lookup_key=lookup_key,
        transfer_lookup_key=True,
        tax_behavior="exclusive",
    )


def main() -> None:
    print(f"Seeding {len(CATALOG)} wine products into Stripe…")
    for entry in CATALOG:
        product = get_or_create_product(entry)
        price = ensure_price(product.id, entry)
        print(f"  ✓ {entry['id']:<30}  price={price.id}  lookup={price.lookup_key}  amount={price.unit_amount}")
    print("Done.")


if __name__ == "__main__":
    main()
