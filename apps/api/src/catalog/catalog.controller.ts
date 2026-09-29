import { Controller, Get } from "@nestjs/common";
import { ApiOkResponse } from "@nestjs/swagger";
import { CatalogDto, CatalogService } from "./catalog.service";

// GET /v1/catalog — écran Compétitions (J9, docs/03 §4).
@Controller("catalog")
export class CatalogController {
  constructor(private readonly catalog: CatalogService) {}

  @Get()
  @ApiOkResponse({ type: CatalogDto })
  async get(): Promise<CatalogDto> {
    return this.catalog.getCatalog();
  }
}
