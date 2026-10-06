import { Module } from "@nestjs/common";
import { DbModule } from "../db/db.module";
import { TwitchService } from "./twitch.service";

@Module({ imports: [DbModule], providers: [TwitchService] })
export class StreamsModule {}
