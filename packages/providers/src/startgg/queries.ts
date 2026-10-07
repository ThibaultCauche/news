// Plafond de 1 000 objets par requête côté start.gg : les pages restent petites (vérifié le 2026-10-07).
export const TOURNAMENTS_QUERY = `query($page:Int,$after:Timestamp,$before:Timestamp,$featured:Boolean,$picks:Boolean){tournaments(query:{perPage:40,page:$page,sortBy:"startAt asc",filter:{videogameIds:[1386],isFeatured:$featured,staffPicks:$picks,afterDate:$after,beforeDate:$before}}){pageInfo{totalPages} nodes{id name slug startAt endAt isOnline events(filter:{videogameId:[1386]}){id name numEntrants}}}}`;

export const PHASES_QUERY = `query($id:ID){event(id:$id){phases{id name bracketType groupCount numSeeds phaseOrder state}}}`;

const SET_FIELDS = `id identifier round fullRoundText state totalGames winnerId startAt startedAt completedAt phaseGroup{id displayIdentifier phase{id}} games{orderNum winnerId} slots{slotIndex prereqType prereqId prereqPlacement entrant{id name participants{gamerTag user{id}}} standing{stats{score{value}}}}`;

// Sets d'une phase (démo seulement : un passage de production lit les sets de l'événement entier).
export const PHASE_SETS_QUERY = `query($id:ID,$page:Int){phase(id:$id){sets(page:$page,perPage:30,sortType:STANDARD){pageInfo{totalPages} nodes{${SET_FIELDS}}}}}`;

export const EVENT_SETS_QUERY = `query($id:ID,$page:Int,$updatedAfter:Timestamp){event(id:$id){sets(page:$page,perPage:30,sortType:STANDARD,filters:{updatedAfter:$updatedAfter}){pageInfo{totalPages} nodes{${SET_FIELDS}}}}}`;

// Personnages par manche (J27) : une requête à part, seulement pour les phases à arbre. Dans la requête principale
// ils feraient dépasser le plafond de 1 000 objets avec 30 sets par page.
export const PHASE_CHARACTERS_QUERY = `query($id:ID,$page:Int,$updatedAfter:Timestamp){phase(id:$id){sets(page:$page,perPage:15,sortType:STANDARD,filters:{updatedAfter:$updatedAfter}){pageInfo{totalPages} nodes{id games{orderNum winnerId selections{entrant{id} character{name}}}}}}}`;

export const SET_QUERY = `query($id:ID){set(id:$id){${SET_FIELDS}}}`;

export const PHASE_LINKS_QUERY = `query($id:ID,$page:Int){phase(id:$id){bracketType sets(page:$page,perPage:60,sortType:STANDARD){pageInfo{totalPages} nodes{id slots{slotIndex prereqType prereqId prereqPlacement}}}}}`;
