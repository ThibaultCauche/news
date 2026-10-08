// Formes brutes de Jolpica-F1 (format Ergast), réduites à ce que l'adaptateur lit.
export interface RawSession {
  date: string;
  time?: string;
}

export interface RawRace {
  season: string;
  round: string;
  raceName: string;
  Circuit: { circuitId: string; circuitName: string; Location: { locality: string; country: string } };
  date: string;
  time?: string;
  FirstPractice?: RawSession;
  SecondPractice?: RawSession;
  ThirdPractice?: RawSession;
  SprintQualifying?: RawSession;
  Sprint?: RawSession;
  Qualifying?: RawSession;
  // Résultats, présents seulement sur les routes /results, /sprint et /qualifying.
  Results?: RawResult[];
  SprintResults?: RawResult[];
  QualifyingResults?: RawQualifying[];
}

export interface RawDriver {
  driverId: string;
  permanentNumber?: string;
  code?: string;
  givenName: string;
  familyName: string;
  nationality?: string;
}

export interface RawConstructor {
  constructorId: string;
  name: string;
  nationality?: string;
}

export interface RawResult {
  position: string;
  positionText: string;
  points: string;
  Driver: RawDriver;
  Constructor: RawConstructor;
  grid?: string;
  laps?: string;
  status: string;
  Time?: { time: string };
}

export interface RawQualifying {
  position: string;
  Driver: RawDriver;
  Constructor: RawConstructor;
  Q1?: string;
  Q2?: string;
  Q3?: string;
}

export interface RawDriverStanding {
  position: string;
  points: string;
  wins: string;
  Driver: RawDriver;
  Constructors: RawConstructor[];
}

export interface RawConstructorStanding {
  position: string;
  points: string;
  wins: string;
  Constructor: RawConstructor;
}

export interface MRData<T> {
  MRData: T;
}
