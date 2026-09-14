"""
SmartSplit AI - Backend
========================
FastAPI + MySQL + Google Gemini 1.5 Flash backend for AI-powered receipt
parsing, itemized expense splitting, and group debt minimization.

Endpoints:
    POST /api/upload-receipt   -> AI-parse a receipt image or pasted text
    POST /api/add-expense      -> Persist a confirmed expense + per-user splits
    GET  /api/settlements      -> Compute minimal set of settling transactions
"""

import json
import logging
import os
from contextlib import contextmanager
from decimal import Decimal, ROUND_HALF_UP
from heapq import heappush, heappop
from typing import Dict, Generator, List, Optional

from google import genai
from google.genai import types
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator

from db import get_db_connection
from dotenv import load_dotenv
load_dotenv()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("smartsplit")

app = FastAPI(title="SmartSplit AI Backend", version="1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # tighten to your deployed frontend origin before shipping
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

GEMINI_API_KEY = os.environ["GEMINI_API_KEY"]  # fails fast if unset - never hardcode a fallback key
client = genai.Client(api_key=GEMINI_API_KEY)

VALID_CATEGORIES = [
    "Food & Dining",
    "Travel & Cabs",
    "Groceries",
    "Rent & Utilities",
    "Entertainment",
    "Miscellaneous",
]

# Money is handled in Decimal internally and only cast to float at the
# API/DB boundary, since float arithmetic on currency silently drifts
# (0.1 + 0.2 != 0.3) and that drift compounds across many small item splits.
TWO_PLACES = Decimal("0.01")


def to_money(value) -> Decimal:
    """Coerce any numeric input into a 2-decimal-place Decimal, safely."""
    try:
        d = Decimal(str(value))
    except Exception:
        d = Decimal("0")
    return d.quantize(TWO_PLACES, rounding=ROUND_HALF_UP)


# -------------------------------------------------------------------
# 1. PYDANTIC MODELS (Data Schemas)
# -------------------------------------------------------------------

class ItemClaim(BaseModel):
    item_name: str = "Uncategorized Item"
    price: float = Field(default=0.0, ge=0)
    claimed_by_user_ids: List[int] = Field(default_factory=list)


class AddExpenseRequest(BaseModel):
    title: str = "Unnamed Expense"
    total_amount: float = Field(default=0.0, ge=0)
    tax_and_fees: float = Field(default=0.0, ge=0)
    paid_by_user_id: int
    category: str = "Miscellaneous"
    item_claims: List[ItemClaim] = Field(default_factory=list)

    @field_validator("category")
    @classmethod
    def validate_category(cls, v: str) -> str:
        return v if v in VALID_CATEGORIES else "Miscellaneous"

class GroupCreateRequest(BaseModel):
    name: str
    member_user_ids: List[int]

class LoginRequest(BaseModel):
    email: str
    password: str


class SettlementTransaction(BaseModel):
    from_user_id: int
    from_user_name: str
    to_user_id: int
    to_user_name: str
    amount: float


class ParsedReceiptItem(BaseModel):
    name: str = "Uncategorized Item"
    price: float = 0.0


class ParsedReceipt(BaseModel):
    title: str = "Parsed Expense"
    total_amount: float = 0.0
    tax_and_fees: float = 0.0
    category: str = "Miscellaneous"
    items: List[ParsedReceiptItem] = Field(default_factory=list)


# -------------------------------------------------------------------
# 2. DB CONNECTION HELPER
# -------------------------------------------------------------------

@contextmanager
def db_cursor(commit: bool = False) -> Generator:
    """
    Context manager wrapping db.py's get_db_connection so every endpoint
    gets automatic commit/rollback/close instead of repeating try/finally
    blocks (and forgetting one of them) in every route.
    """
    conn = get_db_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="Database connection failed.")
    cursor = conn.cursor(dictionary=True)
    try:
        yield cursor
        if commit:
            conn.commit()
    except HTTPException:
        conn.rollback()
        raise
    except Exception as e:
        conn.rollback()
        logger.exception("Database operation failed")
        raise HTTPException(status_code=500, detail=f"Database error: {e}") from e
    finally:
        cursor.close()
        conn.close()


# -------------------------------------------------------------------
# 3. GEMINI AI PARSER HELPER
# -------------------------------------------------------------------

SYSTEM_PROMPT = """
You are an expert financial receipt parser. Analyze the provided image or text
and extract the bill details.

CRITICAL INSTRUCTIONS FOR EDGE CASES:
1. If an item name is blurry, cut off, or illegible, name it "Uncategorized Item".
2. If an individual item's price is unreadable, estimate it so that the sum of
   all item prices plus tax_and_fees is as close as possible to total_amount.
   Never leave a price blank or null - fall back to 0.0 if truly unrecoverable.
3. Extract individual item prices cleanly, using the raw numeric value only.
4. Categorize the bill into exactly ONE of: Food & Dining, Travel & Cabs,
   Groceries, Rent & Utilities, Entertainment, Miscellaneous.
5. If the input is a casual group-chat message instead of a formal receipt,
   infer reasonable item names and prices from context.
"""


FALLBACK_RECEIPT = ParsedReceipt(
    title="Parsed Expense",
    total_amount=0.0,
    tax_and_fees=0.0,
    category="Miscellaneous",
    items=[ParsedReceiptItem(name="Uncategorized Item", price=0.0)],
)


def parse_receipt_with_gemini(
    content_bytes: Optional[bytes] = None,
    mime_type: str = "image/jpeg",
    text_prompt: Optional[str] = None,
) -> ParsedReceipt:
    """
    Calls Gemini 2.5 Flash (google-genai SDK) to extract structured bill
    data from an image or raw text. Passing our Pydantic model directly as
    response_schema makes the SDK both constrain generation to that shape
    AND parse it for us via response.parsed - no manual json.loads or
    markdown-fence stripping needed.
    Falls back to a safe default ParsedReceipt if the call or parse fails,
    so a bad/blurry receipt never bubbles up as a 500 to the frontend.
    """
    config = types.GenerateContentConfig(
        response_mime_type="application/json",
        response_schema=ParsedReceipt,
    )

    try:
        if content_bytes:
            contents = [
                SYSTEM_PROMPT,
                types.Part.from_bytes(data=content_bytes, mime_type=mime_type),
            ]
        elif text_prompt:
            contents = [SYSTEM_PROMPT, f"Group chat / text input:\n{text_prompt}"]
        else:
            raise ValueError("Either content_bytes or text_prompt must be provided.")

        response = client.models.generate_content(
            model="gemini-3.6-flash",
            contents=contents,
            config=config,
        )

        parsed = response.parsed
        if parsed is None:
            # Schema-constrained but still came back empty/unparseable
            raise ValueError("Gemini returned no parsed content.")
        return parsed

    except Exception as e:
        logger.warning("Gemini parse failed, returning fallback receipt: %s", e)
        return FALLBACK_RECEIPT


# -------------------------------------------------------------------
# 4. DEBT MINIMIZATION
# -------------------------------------------------------------------

def compute_net_balances(cursor) -> Dict[int, Decimal]:
    """
    net_balance[user] = total they paid upfront across all expenses
                       - total they owe across all splits.
    Positive  -> owed money (creditor). Negative -> owes money (debtor).
    """
    cursor.execute("SELECT id, name FROM users")
    users = {row["id"]: row["name"] for row in cursor.fetchall()}

    cursor.execute(
        "SELECT paid_by_user_id, SUM(total_amount) AS total_paid "
        "FROM expenses GROUP BY paid_by_user_id"
    )
    paid = {row["paid_by_user_id"]: to_money(row["total_paid"]) for row in cursor.fetchall()}

    cursor.execute(
        "SELECT user_id, SUM(amount_owed) AS total_owed "
        "FROM splits GROUP BY user_id"
    )
    owed = {row["user_id"]: to_money(row["total_owed"]) for row in cursor.fetchall()}

    balances = {}
    for uid in users:
        balances[uid] = to_money(paid.get(uid, Decimal("0")) - owed.get(uid, Decimal("0")))
    return balances, users


def minimize_transactions(
    balances: Dict[int, Decimal], users: Dict[int, str]
) -> List[SettlementTransaction]:
    """
    Greedy debt-minimization: at every step, match the single biggest
    creditor against the single biggest debtor and settle as much of that
    pair as possible. Using max-heaps (rather than a single sorted pass)
    means each settlement re-competes for "biggest" next, which is what
    actually collapses multi-party chains (A->B->C) into the fewest direct
    payments, instead of just processing people in balance order.
    """
    EPSILON = Decimal("0.01")

    debtor_heap: List[tuple] = []   # max-heap via negated amount: (-amount, uid)
    creditor_heap: List[tuple] = []

    for uid, balance in balances.items():
        if balance < -EPSILON:
            heappush(debtor_heap, (balance, uid))          # balance already negative
        elif balance > EPSILON:
            heappush(creditor_heap, (-balance, uid))       # negate to reuse min-heap as max-heap

    transactions: List[SettlementTransaction] = []

    while debtor_heap and creditor_heap:
        debt_amount, debtor_id = heappop(debtor_heap)       # debt_amount is negative
        credit_amount_neg, creditor_id = heappop(creditor_heap)

        owe = -debt_amount
        owed_to = -credit_amount_neg
        settle_amount = to_money(min(owe, owed_to))

        if settle_amount > 0:
            transactions.append(
                SettlementTransaction(
                    from_user_id=debtor_id,
                    from_user_name=users.get(debtor_id, f"User {debtor_id}"),
                    to_user_id=creditor_id,
                    to_user_name=users.get(creditor_id, f"User {creditor_id}"),
                    amount=float(settle_amount),
                )
            )

        remaining_owe = to_money(owe - settle_amount)
        remaining_owed = to_money(owed_to - settle_amount)

        if remaining_owe > EPSILON:
            heappush(debtor_heap, (-remaining_owe, debtor_id))
        if remaining_owed > EPSILON:
            heappush(creditor_heap, (-remaining_owed, creditor_id))

    return transactions


# -------------------------------------------------------------------
# 5. FASTAPI ENDPOINTS
# -------------------------------------------------------------------

@app.get("/")
def root():
    return {"status": "Online", "app": "SmartSplit AI Backend"}


@app.post("/api/upload-receipt")
async def upload_receipt(
    file: Optional[UploadFile] = File(None),
    raw_text: Optional[str] = Form(None),
):
    """
    Accepts a receipt image OR pasted text and returns structured AI JSON
    for the frontend's item-claiming review screen.
    """
    if not file and not raw_text:
        raise HTTPException(
            status_code=400, detail="Please upload an image file or provide text."
        )

    if file:
        if file.content_type not in ("image/jpeg", "image/png", "image/webp", "image/heic"):
            raise HTTPException(
                status_code=400,
                detail=f"Unsupported image type: {file.content_type}. "
                       "Use JPEG, PNG, WEBP, or HEIC.",
            )
        image_bytes = await file.read()
        if not image_bytes:
            raise HTTPException(status_code=400, detail="Uploaded file is empty.")
        parsed = parse_receipt_with_gemini(content_bytes=image_bytes, mime_type=file.content_type)
    else:
        if not raw_text.strip():
            raise HTTPException(status_code=400, detail="raw_text cannot be empty.")
        parsed = parse_receipt_with_gemini(text_prompt=raw_text)

    return {"success": True, "data": parsed.model_dump()}


@app.post("/api/add-expense")
def add_expense(payload: AddExpenseRequest):
    """
    Stores a verified expense and calculates each claimant's share,
    splitting shared items equally and distributing tax/fees proportionally
    to each user's item subtotal.
    """
    if not payload.item_claims:
        raise HTTPException(status_code=400, detail="item_claims cannot be empty.")

    total_amount = to_money(payload.total_amount)
    tax_and_fees = to_money(payload.tax_and_fees)

    # --- Step A: per-user item subtotals (equal split within each claim) ---
    user_subtotals: Dict[int, Decimal] = {}
    total_items_subtotal = Decimal("0")

    for claim in payload.item_claims:
        if not claim.claimed_by_user_ids:
            continue  # an unclaimed item contributes nothing to anyone's share
        price = to_money(claim.price)
        n = len(claim.claimed_by_user_ids)
        split_cost = (price / n).quantize(TWO_PLACES, rounding=ROUND_HALF_UP)

        for uid in claim.claimed_by_user_ids:
            user_subtotals[uid] = user_subtotals.get(uid, Decimal("0")) + split_cost
        total_items_subtotal += split_cost * n

    if not user_subtotals:
        raise HTTPException(
            status_code=400, detail="No items were claimed by any user."
        )

    # --- Step B: proportional tax/fee allocation ---
    user_final_shares: Dict[int, Decimal] = {}
    for uid, subtotal in user_subtotals.items():
        if total_items_subtotal > 0:
            tax_share = (subtotal / total_items_subtotal) * tax_and_fees
        else:
            tax_share = Decimal("0")
        user_final_shares[uid] = to_money(subtotal + tax_share)

    # Per-item / per-tax rounding (splitting price/n, then rounding) can leave
    # the sum of shares a cent or two off the stated total. Reconcile that
    # drift onto whichever user owes the most, rather than losing/inventing
    # money relative to the receipt total.
    computed_total = sum(user_final_shares.values())
    target_total = to_money(total_items_subtotal + tax_and_fees)
    drift = to_money(target_total - computed_total)
    if drift != 0 and user_final_shares:
        largest_uid = max(user_final_shares, key=user_final_shares.get)
        user_final_shares[largest_uid] = to_money(user_final_shares[largest_uid] + drift)

    with db_cursor(commit=True) as cursor:
        cursor.execute(
            """
            INSERT INTO expenses (title, total_amount, paid_by_user_id, category)
            VALUES (%s, %s, %s, %s)
            """,
            (payload.title, float(total_amount), payload.paid_by_user_id, payload.category),
        )
        expense_id = cursor.lastrowid

        cursor.executemany(
            "INSERT INTO splits (expense_id, user_id, amount_owed) VALUES (%s, %s, %s)",
            [(expense_id, uid, float(amt)) for uid, amt in user_final_shares.items()],
        )

    return {
        "success": True,
        "expense_id": expense_id,
        "splits": {uid: float(amt) for uid, amt in user_final_shares.items()},
    }


@app.get("/api/settlements", response_model=List[SettlementTransaction])
def get_settlements():
    """
    Computes each user's net balance across all expenses/splits, then runs
    the greedy heap-based debt-minimization algorithm to collapse chain
    debts (A owes B, B owes C) into the minimum number of direct payments.
    """
    with db_cursor(commit=False) as cursor:
        balances, users = compute_net_balances(cursor)

    if not users:
        return []

    return minimize_transactions(balances, users)

# -------------------------------------------------------------------
# AUTH, GROUPS & PER-GROUP UPI SETTLEMENTS
# -------------------------------------------------------------------

@app.post("/api/login")
def login(payload: LoginRequest):
    """
    Lightweight Auth Endpoint for Hackathon Demo.
    """
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT id, name, email, upi_id FROM users WHERE email = %s", (payload.email,))
    user = cursor.fetchone()
    cursor.close()
    conn.close()

    if not user:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    return {"success": True, "user": user}


@app.post("/api/groups")
def create_group(payload: GroupCreateRequest):
    """
    Create a new group (e.g. 'Goa Trip', 'Roommates') and assign members.
    """
    conn = get_db_connection()
    cursor = conn.cursor()
    
    try:
        cursor.execute("INSERT INTO `groups` (name) VALUES (%s)", (payload.name,))
        group_id = cursor.lastrowid

        member_records = [(group_id, uid) for uid in payload.member_user_ids]
        cursor.executemany("INSERT INTO group_members (group_id, user_id) VALUES (%s, %s)", member_records)
        
        conn.commit()
        return {"success": True, "group_id": group_id, "name": payload.name}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conn.close()


@app.get("/api/settlements/{group_id}")
def get_group_settlements(group_id: int):
    """
    Runs debt minimization specifically isolated to a single group with UPI Payment Links.
    """
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)

    try:
        # Fetch members in this specific group
        cursor.execute("""
            SELECT u.id, u.name, u.upi_id 
            FROM users u 
            JOIN group_members gm ON u.id = gm.user_id 
            WHERE gm.group_id = %s
        """, (group_id,))
        group_users = {u['id']: u for u in cursor.fetchall()}

        if not group_users:
            return []

        # Fetch net paid in this group
        cursor.execute("""
            SELECT paid_by_user_id, SUM(total_amount) as total_paid 
            FROM expenses WHERE group_id = %s GROUP BY paid_by_user_id
        """, (group_id,))
        paid_data = {row['paid_by_user_id']: float(row['total_paid']) for row in cursor.fetchall()}

        # Fetch net owed in this group
        cursor.execute("""
            SELECT s.user_id, SUM(s.amount_owed) as total_owed 
            FROM splits s 
            JOIN expenses e ON s.expense_id = e.id 
            WHERE e.group_id = %s GROUP BY s.user_id
        """, (group_id,))
        owed_data = {row['user_id']: float(row['total_owed']) for row in cursor.fetchall()}

        # Net Balances
        net_balances = {}
        for uid in group_users.keys():
            net_balances[uid] = round(paid_data.get(uid, 0.0) - owed_data.get(uid, 0.0), 2)

        # Greedy Debt Minimization
        debtors = [{'id': uid, 'amount': -bal} for uid, bal in net_balances.items() if bal < -0.01]
        creditors = [{'id': uid, 'amount': bal} for uid, bal in net_balances.items() if bal > 0.01]

        transactions = []
        i, j = 0, 0

        while i < len(debtors) and j < len(creditors):
            settle_amount = round(min(debtors[i]['amount'], creditors[j]['amount']), 2)
            
            if settle_amount > 0:
                to_user = group_users[creditors[j]['id']]
                from_user = group_users[debtors[i]['id']]
                
                # Standard NPCI UPI Deep Link String
                upi_link = f"upi://pay?pa={to_user['upi_id']}&pn={to_user['name']}&am={settle_amount}&cu=INR" if to_user['upi_id'] else None

                transactions.append({
                    "from_user_id": from_user['id'],
                    "from_user_name": from_user['name'],
                    "to_user_id": to_user['id'],
                    "to_user_name": to_user['name'],
                    "amount": settle_amount,
                    "upi_link": upi_link
                })

            debtors[i]['amount'] -= settle_amount
            creditors[j]['amount'] -= settle_amount

            if round(debtors[i]['amount'], 2) == 0: i += 1
            if round(creditors[j]['amount'], 2) == 0: j += 1

        return transactions

    finally:
        cursor.close()
        conn.close()
