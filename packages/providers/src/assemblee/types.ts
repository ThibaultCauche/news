// Formes minimales de l'open data de l'Assemblée nationale (17ᵉ législature), seulement ce que l'adaptateur lit.
// Un élément unique est parfois un objet au lieu d'un tableau : `arr` dans normalize.ts s'en occupe.

export interface RawScrutin {
  uid: string;
  numero: string;
  dateScrutin: string;
  typeVote?: { codeTypeVote?: string; libelleTypeVote?: string };
  sort?: { code?: string; libelle?: string };
  titre?: string;
  objet?: { libelle?: string; dossierLegislatif?: { dossierRef?: string; libelle?: string } | null };
  syntheseVote?: {
    nombreVotants?: string;
    nbrSuffragesRequis?: string;
    annonce?: string;
    decompte?: { nonVotants?: string; pour?: string; contre?: string; abstentions?: string };
  };
  ventilationVotes?: {
    organe?: {
      groupes?: {
        groupe?: RawScrutinGroup | RawScrutinGroup[];
      };
    };
  };
}

export interface RawScrutinGroup {
  organeRef: string;
  nombreMembresGroupe?: string;
  vote?: { decompteVoix?: { nonVotants?: string; pour?: string; contre?: string; abstentions?: string } };
}

export interface RawOrgane {
  uid: string;
  codeType: string;
  libelle: string;
  libelleAbrev?: string;
  legislature?: string;
}

export interface RawAct {
  codeActe: string;
  dateActe?: string | null;
  statutConclusion?: { libelle?: string } | null;
  codeLoi?: string | null;
  titreLoi?: string | null;
  infoJO?: { urlLegifrance?: string | null } | null;
  actesLegislatifs?: { acteLegislatif?: RawAct | RawAct[] } | null;
}

export interface RawDossier {
  uid: string;
  titreDossier: { titre: string; titreChemin?: string };
  procedureParlementaire: { libelle: string };
  initiateur?: { acteurs?: { acteur?: { acteurRef: string } | { acteurRef: string }[] } | null } | null;
  actesLegislatifs?: { acteLegislatif?: RawAct | RawAct[] } | null;
}

export interface RawActeur {
  uid: string | { "#text": string };
  etatCivil?: { ident?: { civ?: string; prenom?: string; nom?: string } };
  mandats?: { mandat?: RawMandat | RawMandat[] };
}

export interface RawMandat {
  typeOrgane?: string;
  dateDebut?: string;
  organes?: { organeRef?: string };
}

// Texte déposé ou adopté : son titre est celui que citent les scrutins, son `dossierRef` retrouve le dossier.
export interface RawDocument {
  dossierRef?: string;
  titres?: { titrePrincipal?: string };
}
