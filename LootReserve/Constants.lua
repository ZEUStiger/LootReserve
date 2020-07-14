LootReserve = LootReserve or { };
LootReserve.Constants =
{
    ReserveResult =
    {
        OK = 0,
        NotInRaid = 1,
        NoSession = 2,
        NotMember = 3,
        ItemNotReservable = 4,
        AlreadyReserved = 5,
        NoReservesLeft = 6,
    },
    CancelReserveResult =
    {
        OK = 0,
        NotInRaid = 1,
        NoSession = 2,
        NotMember = 3,
        ItemNotReservable = 4,
        NotReserved = 5,
        Forced = 6,
    },
    ReservesSorting =
    {
        ByTime = 0,
        ByName = 1,
        BySource = 2,
        ByLooter = 3,
    },
    ChatAnnouncement =
    {
        SessionStart = 1,
        SessionResume = 2,
        SessionStop = 3,
        LootRollStartReserved = 4,
        LootRollStartCustom = 5,
        LootRollWinner = 6,
        LootRollTie = 7,
    },
};