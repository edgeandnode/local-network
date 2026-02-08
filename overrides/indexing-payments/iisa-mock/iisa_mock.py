"""
Mock IISA Service for local development.

This service provides the endpoints expected by dipper's HTTP client:
- GET /health - Health check
- POST /select-one - Select single indexer from candidates
- POST /select-many - Select multiple indexers from candidates

For local testing, it simply returns the first candidate(s) from the list,
since there's no BigQuery performance data available.
"""

import logging
from typing import Optional

from fastapi import FastAPI
from pydantic import BaseModel

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger("iisa-mock")


# Request/Response Models matching dipper's expectations


class CandidateIndexer(BaseModel):
    id: str
    url: str


class SelectionRequest(BaseModel):
    deployment_id: str
    candidates: Optional[list[CandidateIndexer]] = None
    existing_indexers: Optional[list[str]] = None
    pending_agreements: Optional[dict[str, list[str]]] = None
    num_candidates: Optional[int] = None
    indexer_denylist: Optional[list[str]] = None
    declined_indexers: Optional[dict[str, list[str]]] = None


class SingleSelectionResponse(BaseModel):
    indexer_id: Optional[str] = None


class MultiSelectionResponse(BaseModel):
    indexer_ids: list[str]


class HealthResponse(BaseModel):
    status: str
    data_loaded: bool


# FastAPI Application

app = FastAPI(
    title="IISA Mock Service",
    description="Mock Indexing Indexer Selection Algorithm for local development",
    version="0.1.0",
)


@app.get("/health", response_model=HealthResponse)
async def health_check() -> HealthResponse:
    """Health check endpoint."""
    return HealthResponse(status="healthy", data_loaded=True)


@app.post("/select-one", response_model=SingleSelectionResponse)
async def select_one(request: SelectionRequest) -> SingleSelectionResponse:
    """
    Select one indexer from candidates.

    For local testing, returns the first eligible candidate
    (not in denylist, not already existing, not declined).
    """
    logger.info(f"select-one request for deployment {request.deployment_id}")

    if not request.candidates:
        logger.info("No candidates provided, returning None")
        return SingleSelectionResponse(indexer_id=None)

    # Build set of excluded indexers
    excluded = set()
    if request.indexer_denylist:
        excluded.update(request.indexer_denylist)
    if request.existing_indexers:
        excluded.update(request.existing_indexers)
    if request.declined_indexers and request.deployment_id in request.declined_indexers:
        excluded.update(request.declined_indexers[request.deployment_id])

    # Find first eligible candidate
    for candidate in request.candidates:
        if candidate.id not in excluded:
            logger.info(f"Selected indexer: {candidate.id}")
            return SingleSelectionResponse(indexer_id=candidate.id)

    logger.info("No eligible candidates found")
    return SingleSelectionResponse(indexer_id=None)


@app.post("/select-many", response_model=MultiSelectionResponse)
async def select_many(request: SelectionRequest) -> MultiSelectionResponse:
    """
    Select multiple indexers from candidates.

    For local testing, returns the first N eligible candidates
    where N = num_candidates (default 3).
    """
    logger.info(
        f"select-many request for deployment {request.deployment_id}, "
        f"num_candidates={request.num_candidates}"
    )

    if not request.candidates:
        logger.info("No candidates provided, returning empty list")
        return MultiSelectionResponse(indexer_ids=[])

    num_to_select = request.num_candidates or 3

    # Build set of excluded indexers
    excluded = set()
    if request.indexer_denylist:
        excluded.update(request.indexer_denylist)
    if request.existing_indexers:
        excluded.update(request.existing_indexers)
    if request.declined_indexers and request.deployment_id in request.declined_indexers:
        excluded.update(request.declined_indexers[request.deployment_id])

    # Select eligible candidates up to num_to_select
    selected = []
    for candidate in request.candidates:
        if candidate.id not in excluded:
            selected.append(candidate.id)
            if len(selected) >= num_to_select:
                break

    logger.info(f"Selected {len(selected)} indexers: {selected}")
    return MultiSelectionResponse(indexer_ids=selected)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
