import { ApiProperty } from "@nestjs/swagger";
import { IsString, MinLength } from "class-validator";

export class FirebaseLoginDto {
  @ApiProperty({ description: "ID token Firebase Auth de l'utilisateur connecté" })
  @IsString()
  @MinLength(10)
  idToken!: string;
}
