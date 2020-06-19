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
};