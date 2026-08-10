import { Global, Module } from '@nestjs/common';
import { GridService } from './grid.service';
import { GridController } from './grid.controller';

@Global()
@Module({ providers: [GridService], controllers: [GridController], exports: [GridService] })
export class GridModule {}
