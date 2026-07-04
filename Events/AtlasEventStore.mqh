//+------------------------------------------------------------------+
//|                  Events/AtlasEventStore.mqh                     |
//|       AtlasEA v0.1.19.0 - Event Store Implementation            |
//+------------------------------------------------------------------+
#ifndef ATLAS_ATLAS_EVENT_STORE_MQH
#define ATLAS_ATLAS_EVENT_STORE_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Interfaces/IEventStore.mqh"
#include "../Interfaces/ILogger.mqh"
#include "EventMetadata.mqh"
#include "EventJournal.mqh"
#include "EventVersioning.mqh"
#include "EventFactory.mqh"
#include "../Core/ValidationResult.mqh"

/**
 * @brief Maximum events returned by a single query.
 */
#define ATLAS_EVENT_QUERY_MAX 128

/**
 * @class AtlasEventStore
 * @brief Concrete implementation of IEventStore.
 *
 * Uses an EventJournal (ring buffer) as the backing store.
 * Supports append, read, range, and filtered queries.
 *
 * The store assigns sequence numbers and validates event versions.
 */
class AtlasEventStore : public IEventStore
{
private:
    ILogger      *m_logger;
    EventJournal  m_journal;

public:
    /**
     * @brief Constructor.
     */
    AtlasEventStore(void) { m_logger = NULL; }

    void SetLogger(ILogger *logger) { m_logger = logger; m_journal.SetLogger(logger); }

    //=== IEventStore implementation ===

    virtual bool Append(const AtlasEvent &event) override
    {
        //--- Validate incoming event (Design by Contract)
        ValidationResult ev_check = event.Validate();
        if(!ev_check.valid)
        {
            if(m_logger != NULL)
                m_logger.Error("AtlasEventStore",
                               "Reject invalid event: " + ev_check.Summary());
            return false;
        }

        //--- Create metadata
        EventMetadata meta = EventFactory::CreateMetadata(event, "", "", ATLAS_LOG_INFO);

        //--- Create sourced event
        SourcedEvent sourced(event, meta);

        //--- Version check
        if(!EventVersioning::IsCompatible((int)event.type, meta.event_version))
        {
            if(m_logger != NULL)
                m_logger.Warn("AtlasEventStore", "Incompatible event version");
        }

        //--- Append to journal
        long seq = m_journal.Append(sourced);
        if(seq == 0)
        {
            if(m_logger != NULL)
                m_logger.Error("AtlasEventStore", "Append failed");
            return false;
        }

        return true;
    }

    /**
     * @brief Append a pre-built SourcedEvent (with full metadata).
     */
    bool AppendSourced(SourcedEvent &sourced)
    {
        //--- Version check + upgrade
        if(!EventVersioning::Upgrade(sourced))
        {
            if(m_logger != NULL)
                m_logger.Warn("AtlasEventStore", "Event upgrade failed");
        }

        long seq = m_journal.Append(sourced);
        return (seq > 0);
    }

    virtual bool Read(const long sequence, AtlasEvent &out) const override
    {
        SourcedEvent sourced;
        if(!m_journal.Read(sequence, sourced)) return false;
        out = sourced.event;
        return true;
    }

    /**
     * @brief Read a sourced event (with metadata) by sequence.
     */
    bool ReadSourced(const long sequence, SourcedEvent &out) const
    {
        return m_journal.Read(sequence, out);
    }

    virtual int ReadRange(const long from_seq, const long to_seq,
                           AtlasEvent out_events[], const int max_count) const override
    {
        SourcedEvent sourced[ATLAS_EVENT_QUERY_MAX];
        int cap = (max_count < ATLAS_EVENT_QUERY_MAX) ? max_count : ATLAS_EVENT_QUERY_MAX;
        int found = m_journal.ReadRange(from_seq, to_seq, sourced, cap);

        for(int i = 0; i < found; i++)
            out_events[i] = sourced[i].event;

        return found;
    }

    virtual int ReadByQuery(const EventQuery &query,
                             AtlasEvent out_events[], const int max_count) const override
    {
        int found = 0;
        int cap = (max_count < ATLAS_EVENT_QUERY_MAX) ? max_count : ATLAS_EVENT_QUERY_MAX;

        for(int i = 0; i < m_journal.Count() && found < cap; i++)
        {
            SourcedEvent sourced;
            if(!m_journal.ReadByIndex(i, sourced)) continue;

            if(MatchesQuery(sourced, query))
            {
                out_events[found] = sourced.event;
                found++;
            }
        }

        return found;
    }

    virtual long Count(void) const override { return (long)m_journal.Count(); }

    virtual long GetNextSequence(void) const override { return m_journal.GetNextSequence(); }

    virtual void Clear(void) override { m_journal.Clear(); }

    //=== Extended API ===

    /**
     * @brief Get the journal (for direct access).
     */
    EventJournal& GetJournal(void) { return m_journal; }

    /**
     * @brief Get oldest sequence in the store.
     */
    long GetOldestSequence(void) const { return m_journal.GetOldestSequence(); }

    /**
     * @brief Get newest sequence.
     */
    long GetNewestSequence(void) const { return m_journal.GetNewestSequence(); }

    /**
     * @brief Validate the event store state.
     * @return ValidationResult.
     *
     * Invariants:
     *   - m_logger may be NULL (acceptable — every use site guards NULL)
     *   - m_journal passes its own Validate()
     */
    ValidationResult Validate(void) const
    {
        //--- m_logger may be NULL (see Append/AppendSourced guards)
        ValidationResult r = m_journal.Validate();
        if(!r.valid)
        {
            if(StringLen(r.field) > 0)
                r.field = "m_journal." + r.field;
            else
                r.field = "m_journal";
            return r;
        }
        return ValidationResult::Ok();
    }

private:
    /// @brief Check if a sourced event matches a query.
    bool MatchesQuery(const SourcedEvent &sourced, const EventQuery &query) const
    {
        switch(query.filter_type)
        {
            case ATLAS_EVENT_FILTER_NONE:
                return true;

            case ATLAS_EVENT_FILTER_TYPE:
                return ((int)sourced.event.type == query.event_type);

            case ATLAS_EVENT_FILTER_SNAPSHOT:
                return (sourced.event.snapshot_id == query.snapshot_id);

            case ATLAS_EVENT_FILTER_CORRELATION:
                return (sourced.metadata.correlation_id == query.correlation_id);

            case ATLAS_EVENT_FILTER_REQUEST:
                return (sourced.metadata.request_id == query.request_id);

            case ATLAS_EVENT_FILTER_STRATEGY:
                //--- Strategy ID is encoded in payload (simplified: check payload[0..3])
                //--- In production, this would deserialize the payload
                return false;  //--- Placeholder

            case ATLAS_EVENT_FILTER_SYMBOL:
                //--- Symbol is not directly in the event; would need payload deserialization
                return false;  //--- Placeholder

            case ATLAS_EVENT_FILTER_TIME:
                if(sourced.event.timestamp < query.from_time) return false;
                if(sourced.event.timestamp > query.to_time) return false;
                return true;

            default:
                return false;
        }
    }
};

#endif // ATLAS_ATLAS_EVENT_STORE_MQH
//+------------------------------------------------------------------+
