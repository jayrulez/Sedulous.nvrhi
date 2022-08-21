using System.Collections;
using System;

namespace System.Collections
{
	extension List<T> where T : struct
	{
		public void Resize(int newSize, T fillValue)
		{
			let currentSize = this.Count;
			this.Count = newSize;
			if (newSize > currentSize)
			{
				for (int i = currentSize; i < newSize; i++)
				{
					this[i] = fillValue;
				}
			}
		}
		public void Fill(T fillValue)
		{
			for (int i = 0; i < Count; i++)
			{
				this[i] = fillValue;
			}
		}
	}
}

namespace nvrhi
{
	interface BufferStateExtension : IHashable
	{
		public readonly ref BufferDesc getDesc();

		public ResourceStates permanentState { get; set; }
	}

	interface TextureStateExtension : IHashable
	{
		public readonly ref TextureDesc getDesc();
		public ResourceStates permanentState { get; set; }
		public bool stateInitialized { get; set; }
	}

	struct TextureState
	{
		public List<ResourceStates> subresourceStates;
		public ResourceStates state = ResourceStates.Unknown;
		public bool enableUavBarriers = true;
		public bool firstUavBarrierPlaced = false;
		public bool permanentTransition = false;
	}

	struct BufferState
	{
		public ResourceStates state = ResourceStates.Unknown;
		public bool enableUavBarriers = true;
		public bool firstUavBarrierPlaced = false;
		public bool permanentTransition = false;
	}

	struct TextureBarrier
	{
		public TextureStateExtension texture = null;
		public MipLevel mipLevel = 0;
		public ArraySlice arraySlice = 0;
		public bool entireTexture = false;
		public ResourceStates stateBefore = ResourceStates.Unknown;
		public ResourceStates stateAfter = ResourceStates.Unknown;
	}

	struct BufferBarrier
	{
		public BufferStateExtension buffer = null;
		public ResourceStates stateBefore = ResourceStates.Unknown;
		public ResourceStates stateAfter = ResourceStates.Unknown;
	}

	public static
	{
		public static bool verifyPermanentResourceState(ResourceStates permanentState, ResourceStates requiredState, bool isTexture, String debugName, IMessageCallback messageCallback)
		{
			if ((permanentState & requiredState) != requiredState)
			{
				String message = scope $"Permanent {(isTexture ? "texture" : "buffer")} {utils.DebugNameToString(debugName)} doesn't have the right state bits. Required: 0x{uint32(requiredState)/*todo:hex*/}, present: 0x{uint32(permanentState)/*todo: hex*/}" ;
		        messageCallback.message(MessageSeverity.Error, message);
		        return false;
		    }

		    return true;
		}

		public static uint32 calcSubresource(MipLevel mipLevel, ArraySlice arraySlice, TextureDesc desc)
		{
		    return mipLevel + arraySlice * desc.mipLevels;
		}
	}

	class CommandListResourceStateTracker
	{
	    public this(IMessageCallback messageCallback)
	    { 
	        m_MessageCallback = messageCallback;
	    }

	    // ICommandList-like interface

	    public void setEnableUavBarriersForTexture(TextureStateExtension texture, bool enableBarriers)
	    {
	        TextureState* tracking = getTextureStateTracking(texture, true);
	
	        tracking.enableUavBarriers = enableBarriers;
	        tracking.firstUavBarrierPlaced = false;
	    }
	    public void setEnableUavBarriersForBuffer(BufferStateExtension buffer, bool enableBarriers)
	    {
	        BufferState* tracking = getBufferStateTracking(buffer, true);
	
	        tracking.enableUavBarriers = enableBarriers;
	        tracking.firstUavBarrierPlaced = false;
	    }

	    public void beginTrackingTextureState(TextureStateExtension texture, TextureSubresourceSet subresources, ResourceStates stateBits)
	    {
	        readonly ref TextureDesc desc = ref texture.getDesc();
	
	        TextureState* tracking = getTextureStateTracking(texture, true);
	
			var subresources;
	        subresources = subresources.resolve(desc, false);
	
	        if (subresources.isEntireTexture(desc))
	        {
	            tracking.state = stateBits;
	            tracking.subresourceStates.Clear();
	        }
	        else
	        {
	            tracking.subresourceStates.Resize(desc.mipLevels * desc.arraySize, tracking.state);
	            tracking.state = ResourceStates.Unknown;
	
	            for (MipLevel mipLevel = subresources.baseMipLevel; mipLevel < subresources.baseMipLevel + subresources.numMipLevels; mipLevel++)
	            {
	                for (ArraySlice arraySlice = subresources.baseArraySlice; arraySlice < subresources.baseArraySlice + subresources.numArraySlices; arraySlice++)
	                {
	                    uint32 subresource = calcSubresource(mipLevel, arraySlice, desc);
	                    tracking.subresourceStates[subresource] = stateBits;
	                }
	            }
	        }
	    }
	    public void beginTrackingBufferState(BufferStateExtension buffer, ResourceStates stateBits)
	    {
	        BufferState* tracking = getBufferStateTracking(buffer, true);
	
	        tracking.state = stateBits;
	    }

	    public void endTrackingTextureState(TextureStateExtension texture, TextureSubresourceSet subresources, ResourceStates stateBits, bool permanent)
	    {
			var subresources;
			var permanent;
	        readonly ref TextureDesc desc = ref texture.getDesc();
	
	        subresources = subresources.resolve(desc, false);
	
	        if (permanent && !subresources.isEntireTexture(desc))
	        {
	            String message = scope $"Attempted to perform a permanent state transition on a subset of subresources of texture {utils.DebugNameToString(desc.debugName)}";
	            m_MessageCallback.message(MessageSeverity.Error, message);
	            permanent = false;
	        }
	
	        requireTextureState(texture, subresources, stateBits);
	
	        if (permanent)
	        {
	            m_PermanentTextureStates.Add((texture, stateBits));
	            getTextureStateTracking(texture, true).permanentTransition = true;
	        }
	    }
	    public void endTrackingBufferState(BufferStateExtension buffer, ResourceStates stateBits, bool permanent)
	    {
	        requireBufferState(buffer, stateBits);
	
	        if (permanent)
	        {
	            m_PermanentBufferStates.Add((buffer, stateBits));
	        }
	    }

	    public ResourceStates getTextureSubresourceState(TextureStateExtension texture, ArraySlice arraySlice, MipLevel mipLevel)
	    {
	        TextureState* tracking = getTextureStateTracking(texture, false);
	
	        if (tracking == null)
	            return ResourceStates.Unknown;
	
	        uint32 subresource = calcSubresource(mipLevel, arraySlice, texture.getDesc());
	        return tracking.subresourceStates[subresource];
	    }
	    public ResourceStates getBufferState(BufferStateExtension buffer)
	    {
	        BufferState* tracking = getBufferStateTracking(buffer, false);
	
	        if (tracking == null)
	            return ResourceStates.Unknown;
	
	        return tracking.state;
	    }

	    // Internal interface
	    
	    public void requireTextureState(TextureStateExtension texture, TextureSubresourceSet subresources, ResourceStates state)
	    {
			var subresources;
	        if (texture.permanentState != 0)
	        {
	            verifyPermanentResourceState(texture.permanentState, state, true, texture.getDesc().debugName, m_MessageCallback);
	            return;
	        }
	
	        subresources = subresources.resolve(texture.getDesc(), false);
	
	        TextureState* tracking = getTextureStateTracking(texture, true);
	        
	        if (subresources.isEntireTexture(texture.getDesc()) && tracking.subresourceStates.IsEmpty)
	        {
	            // We're requiring state for the entire texture, and it's been tracked as entire texture too
	
	            bool transitionNecessary = tracking.state != state;
	            bool uavNecessary = ((state & ResourceStates.UnorderedAccess) != 0)
	                && (tracking.enableUavBarriers || !tracking.firstUavBarrierPlaced);
	
	            if (transitionNecessary || uavNecessary)
	            {
	                TextureBarrier barrier = .();
	                barrier.texture = texture;
	                barrier.entireTexture = true;
	                barrier.stateBefore = tracking.state;
	                barrier.stateAfter = state;
	                m_TextureBarriers.Add(barrier);
	            }
	
	            tracking.state = state;
	
	            if (uavNecessary && !transitionNecessary)
	            {
	                tracking.firstUavBarrierPlaced = true;
	            }
	        }
	        else
	        {
	            // Transition individual subresources
	
	            // Make sure that we're tracking the texture on subresource level
	            bool stateExpanded = false;
	            if (tracking.subresourceStates.IsEmpty)
	            {
	                if (tracking.state == ResourceStates.Unknown)
	                {
	                    String message = scope $"""
							Unknown prior state of texture {nvrhi.utils.DebugNameToString(texture.getDesc().debugName)}.
							Call CommandList::beginTrackingTextureState(...) before using the texture or use the keepInitialState and initialState members of TextureDesc.
							""";
	                    m_MessageCallback.message(MessageSeverity.Error, message);
	                }
	
	                tracking.subresourceStates.Resize(texture.getDesc().mipLevels * texture.getDesc().arraySize, tracking.state);
	                tracking.state = ResourceStates.Unknown;
	                stateExpanded = true;
	            }
	            
	            bool anyUavBarrier = false;
	
	            for (ArraySlice arraySlice = subresources.baseArraySlice; arraySlice < subresources.baseArraySlice + subresources.numArraySlices; arraySlice++)
	            {
	                for (MipLevel mipLevel = subresources.baseMipLevel; mipLevel < subresources.baseMipLevel + subresources.numMipLevels; mipLevel++)
	                {
	                    uint32 subresourceIndex = calcSubresource(mipLevel, arraySlice, texture.getDesc());
	
	                    var priorState = tracking.subresourceStates[subresourceIndex];
	
	                    if (priorState == ResourceStates.Unknown && !stateExpanded)
	                    {
	                        String message = scope $"""
								Unknown prior state of texture {nvrhi.utils.DebugNameToString(texture.getDesc().debugName)} subresource (MipLevel = {mipLevel}, ArraySlice = {arraySlice}).
								Call CommandList.beginTrackingTextureState(...) before using the texture or use the keepInitialState and initialState members of TextureDesc.
								""";
	                        m_MessageCallback.message(MessageSeverity.Error, message);
	                    }
	                    
	                    bool transitionNecessary = priorState != state;
	                    bool uavNecessary = ((state & ResourceStates.UnorderedAccess) != 0)
	                        && !anyUavBarrier && (tracking.enableUavBarriers || !tracking.firstUavBarrierPlaced);
	
	                    if (transitionNecessary || uavNecessary)
	                    {
	                        TextureBarrier barrier = .();
	                        barrier.texture = texture;
	                        barrier.entireTexture = false;
	                        barrier.mipLevel = mipLevel;
	                        barrier.arraySlice = arraySlice;
	                        barrier.stateBefore = priorState;
	                        barrier.stateAfter = state;
	                        m_TextureBarriers.Add(barrier);
	                    }
	
	                    tracking.subresourceStates[subresourceIndex] = state;
	
	                    if (uavNecessary && !transitionNecessary)
	                    {
	                        anyUavBarrier = true;
	                        tracking.firstUavBarrierPlaced = true;
	                    }
	                }
	            }
	        }
	    }
	    public void requireBufferState(BufferStateExtension buffer, ResourceStates state)
	    {
	        if (buffer.getDesc().isVolatile)
	            return;
	
	        if (buffer.permanentState != 0)
	        {
	            verifyPermanentResourceState(buffer.permanentState, state, false, buffer.getDesc().debugName, m_MessageCallback);
	
	            return;
	        }
	
	        if (buffer.getDesc().cpuAccess != CpuAccessMode.None)
	        {
	            // CPU-visible buffers can't change state
	            return;
	        }
	
	        BufferState* tracking = getBufferStateTracking(buffer, true);
	
	        if (tracking.state == ResourceStates.Unknown)
	        {
	            String message = scope $"""
					Unknown prior state of buffer {nvrhi.utils.DebugNameToString(buffer.getDesc().debugName)}.
					Call CommandList::beginTrackingBufferState(...) before using the buffer or use the keepInitialState and initialState members of BufferDesc.
					""";
	            m_MessageCallback.message(MessageSeverity.Error, message);
	        }
	
	        bool transitionNecessary = tracking.state != state;
	        bool uavNecessary = ((state & ResourceStates.UnorderedAccess) != 0)
	            && (tracking.enableUavBarriers || !tracking.firstUavBarrierPlaced);
	
	        if (transitionNecessary)
	        {
	            // See if this buffer is already used for a different purpose in this batch.
	            // If it is, combine the state bits.
	            // Example: same buffer used as index and vertex buffer, or as SRV and indirect arguments.
	            for (ref BufferBarrier barrier in ref m_BufferBarriers)
	            {
	                if (barrier.buffer == buffer)
	                {
	                    barrier.stateAfter = (ResourceStates)(barrier.stateAfter | state);
	                    tracking.state = barrier.stateAfter;
	                    return;
	                }
	            }
	        }
	
	        if (transitionNecessary || uavNecessary)
	        {
	            BufferBarrier barrier = .();
	            barrier.buffer = buffer;
	            barrier.stateBefore = tracking.state;
	            barrier.stateAfter = state;
	            m_BufferBarriers.Add(barrier);
	        }
	
	        if (uavNecessary && !transitionNecessary)
	        {
	            tracking.firstUavBarrierPlaced = true;
	        }
	    
	        tracking.state = state;
	    }

	    public void keepBufferInitialStates()
	    {
			//, BufferState*
	        for (var (buffer, tracking) in m_BufferStates)
	        {
	            if (buffer.getDesc().keepInitialState && 
	                buffer.permanentState == .Unknown &&
	                !buffer.getDesc().isVolatile &&
	                !tracking.permanentTransition)
	            {
	                requireBufferState(buffer, buffer.getDesc().initialState);
	            }
	        }
	    }
	    public void keepTextureInitialStates()
	    {
	        for (var (texture, tracking) in m_TextureStates)
	        {
	            if (texture.getDesc().keepInitialState && 
	                texture.permanentState == .Unknown && 
	                !tracking.permanentTransition)
	            {
	                requireTextureState(texture, AllSubresources, texture.getDesc().initialState);
	            }
	        }
	    }
	    public void commandListSubmitted()
	    {
	        for (var (texture, state) in m_PermanentTextureStates)
	        {
	            if (texture.permanentState != 0 && texture.permanentState != state)
	            {
	                String message = scope $"Attempted to switch permanent state of texture {nvrhi.utils.DebugNameToString(texture.getDesc().debugName)} from 0x{uint32(texture.permanentState)} to 0x{uint32(state)}";
	                m_MessageCallback.message(MessageSeverity.Error, message);
	                continue;
	            }
	
	            texture.permanentState = state;
	        }
	        m_PermanentTextureStates.Clear();
	
	        for (var (buffer, state) in m_PermanentBufferStates)
	        {
	            if (buffer.permanentState != 0 && buffer.permanentState != state)
	            {
	                String message = scope $"Attempted to switch permanent state of buffer {utils.DebugNameToString(buffer.getDesc().debugName)} from 0x{uint32(buffer.permanentState)} to 0x{uint32(state)}";
	                m_MessageCallback.message(MessageSeverity.Error, message);
	                continue;
	            }
	
	            buffer.permanentState = state;
	        }
	        m_PermanentBufferStates.Clear();
	
	        for (var (texture, stateTracking) in m_TextureStates)
	        {
	            if (texture.getDesc().keepInitialState && !texture.stateInitialized)
	                texture.stateInitialized = true;
	        }
	
	        m_TextureStates.Clear();
	        m_BufferStates.Clear();
	    }

	    [NoDiscard] public List<TextureBarrier> getTextureBarriers() { return m_TextureBarriers; }
	    [NoDiscard] public List<BufferBarrier> getBufferBarriers() { return m_BufferBarriers; }
	    public void clearBarriers() { m_TextureBarriers.Clear(); m_BufferBarriers.Clear(); }


	    private IMessageCallback m_MessageCallback;

	    private Dictionary<TextureStateExtension, TextureState*> m_TextureStates;
	    private Dictionary<BufferStateExtension, BufferState*> m_BufferStates;

	    // Deferred transitions of textures and buffers to permanent states.
	    // They are executed only when the command list is executed, not when the app calls endTrackingTextureState.
	    private List<(TextureStateExtension texture, ResourceStates state)> m_PermanentTextureStates;
	    private List<(BufferStateExtension buffer, ResourceStates state)> m_PermanentBufferStates;

	    private List<TextureBarrier> m_TextureBarriers;
	    private List<BufferBarrier> m_BufferBarriers;

	    private TextureState* getTextureStateTracking(TextureStateExtension texture, bool allowCreate)
	    {
	        if (m_TextureStates.ContainsKey(texture))
	        {
	            return m_TextureStates[texture];
	        }
	
	        if (!allowCreate)
	            return null;
	        
	        TextureState* trackingRef = new TextureState();
	
	        TextureState* tracking = trackingRef;
	        m_TextureStates.Add(texture, trackingRef);
	        
	        if (texture.getDesc().keepInitialState)
	        {
	            tracking.state = texture.stateInitialized ? texture.getDesc().initialState : ResourceStates.Common;
	        }
	
	        return tracking;
	    }
	    private BufferState* getBufferStateTracking(BufferStateExtension buffer, bool allowCreate)
	    {
	        if (m_BufferStates.ContainsKey(buffer))
	        {
	            return m_BufferStates[buffer];
	        }
	
	        if (!allowCreate)
	            return null;
	
	        BufferState* trackingRef = new BufferState();
	
	        BufferState* tracking = trackingRef;
	        m_BufferStates.Add(buffer, trackingRef);
	                                                   
	        if (buffer.getDesc().keepInitialState)
	        {
	            tracking.state = buffer.getDesc().initialState;
	        }
	
	        return tracking;
	    }
	}
}