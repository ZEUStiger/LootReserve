LootReserve = LootReserve or { };
LootReserve.Constants =
{
    ReserveResult =
    {
        OK = 0,
        NoSession = 1,
        NotMember = 2,
        ItemNotReservable = 3,
        AlreadyReserved = 4,
        NoReservesLeft = 5,
    },
    CancelReserveResult =
    {
        OK = 0,
        NoSession = 1,
        NotMember = 2,
        ItemNotReservable = 3,
        NotReserved = 4,
        Forced = 5,
    },
};