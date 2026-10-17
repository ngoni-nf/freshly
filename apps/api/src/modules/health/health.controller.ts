import { Controller, Get } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Public } from '../../common/decorators';
import { DatabaseService } from '../../common/database/database.service';
import { RedisService } from '../../common/redis/redis.service';

@ApiTags('health')
@Controller()
export class HealthController {
  constructor(
    private readonly db: DatabaseService,
    private readonly redis: RedisService,
  ) {}

  /** Liveness: is the process up. Never touches a dependency. */
  @Public()
  @Get('health')
  health() {
    return { status: 'ok', service: 'freshly-api', uptimeSeconds: Math.floor(process.uptime()) };
  }

  /**
   * Readiness: should this instance receive traffic. Checks the dependencies
   * a request actually needs, so a rolling deploy does not route to a pod
   * whose database connection has not come up.
   */
  @Public()
  @Get('ready')
  async ready() {
    const [database, redis] = await Promise.all([this.db.healthy(), this.redis.healthy()]);
    const ready = database && redis;
    return { status: ready ? 'ready' : 'degraded', checks: { database, redis } };
  }
}
