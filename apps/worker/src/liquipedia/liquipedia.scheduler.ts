import { InjectQueue } from "@nestjs/bullmq";
import { Injectable, OnModuleInit } from "@nestjs/common";
import { Queue } from "bullmq";
import { LIQUIPEDIA_QUEUE_NAME } from "./constants";

const JOB_NAME = "refresh";
const EVERY_MS = 24 * 60 * 60 * 1000;

@Injectable()
export class LiquipediaScheduler implements OnModuleInit {
  constructor(@InjectQueue(LIQUIPEDIA_QUEUE_NAME) private readonly queue: Queue) {}

  async onModuleInit(): Promise<void> {
    await this.queue.add(JOB_NAME, {}, { repeat: { every: EVERY_MS }, jobId: JOB_NAME });
    await this.queue.add(JOB_NAME, {});
  }
}
