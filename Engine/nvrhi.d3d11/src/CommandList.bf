using Win32.Graphics.Direct3D11;
using System;
using Win32.Foundation;
using nvrhi.d3dcommon;
namespace nvrhi.d3d11;

class CommandList : RefCounter<ICommandList>
{
    public this(Context* context, IDevice device, CommandListParameters @params){
		m_Context =context;
		m_Device = device;
		m_Desc = @params;

		m_Context.immediateContext.QueryInterface(ID3DUserDefinedAnnotation.IID, (void**)(&m_UserDefinedAnnotation));
	}

    // IResource implementation

    public override NativeObject getNativeObject(ObjectType objectType)
    {
        switch (objectType)
        {
        case ObjectType.D3D11_DeviceContext:
            return NativeObject(m_Context.immediateContext);
        default:
            return null;
        }
    }

    // ICommandList implementation

    public override void open()
    {
        clearState();
    }
    
    public override void close()
    {
        while (m_NumUAVOverlapCommands > 0)
            leaveUAVOverlapSection();

        clearState();
    }
    
    public override void clearState()
    {
        m_Context.immediateContext.ClearState();

#if NVRHI_D3D11_WITH_NVAPI
        if (m_CurrentGraphicsStateValid && m_CurrentSinglePassStereoState.enabled)
        {
            NvAPI_D3D_SetSinglePassStereoMode(m_Context.immediateContext, 1, 0, 0);
        }
#endif

        m_CurrentGraphicsStateValid = false;
        m_CurrentComputeStateValid = false;

        // Release the strong references to pipeline objects
        m_CurrentGraphicsPipeline = null;
        m_CurrentFramebuffer = null;
        m_CurrentBindings.Resize(0);
        m_CurrentVertexBuffers.Resize(0);
        m_CurrentIndexBuffer = null;
        m_CurrentComputePipeline = null;
        m_CurrentIndirectBuffer = null;
        m_CurrentBlendConstantColor = .();
    }

    public override void clearTextureFloat(ITexture _texture, TextureSubresourceSet subresources, Color clearColor)
    {
		var subresources;
        Texture texture = checked_cast<Texture, ITexture>(_texture);

#if DEBUG
        readonly ref FormatInfo formatInfo = ref getFormatInfo(texture.desc.format);
        Runtime.Assert(!formatInfo.hasDepth && !formatInfo.hasStencil);
        Runtime.Assert(texture.desc.isUAV || texture.desc.isRenderTarget);
#endif

        subresources = subresources.resolve(texture.desc, false);
        
        for(MipLevel mipLevel = subresources.baseMipLevel; mipLevel < subresources.baseMipLevel + subresources.numMipLevels; mipLevel++)
        {
            TextureSubresourceSet currentMipSlice = TextureSubresourceSet(mipLevel, 1, subresources.baseArraySlice, subresources.numArraySlices);
            
            if (texture.desc.isUAV)
            {
                ID3D11UnorderedAccessView* uav = texture.getUAV(Format.UNKNOWN, currentMipSlice, TextureDimension.Unknown);

                m_Context.immediateContext.ClearUnorderedAccessViewFloat(uav, &clearColor.r);
            }
            else if (texture.desc.isRenderTarget)
            {
                ID3D11RenderTargetView* rtv = texture.getRTV(Format.UNKNOWN, currentMipSlice);

                m_Context.immediateContext.ClearRenderTargetView(rtv, &clearColor.r);
            }
            else
            {
                break;
            }
        }
    }
    
    public override void clearDepthStencilTexture(ITexture t, TextureSubresourceSet subresources, bool clearDepth, float depth, bool clearStencil, uint8 stencil)
    {
		var subresources;
        if (!clearDepth && !clearStencil)
        {
            return;
        }

        Texture texture = checked_cast<Texture, ITexture>(t);

#if DEBUG
        readonly ref FormatInfo formatInfo = ref getFormatInfo(texture.desc.format);
        Runtime.Assert(texture.desc.isRenderTarget);
        Runtime.Assert(formatInfo.hasDepth || formatInfo.hasStencil);
#endif

        subresources = subresources.resolve(texture.getDesc(), false);

        for (MipLevel mipLevel = subresources.baseMipLevel; mipLevel < subresources.baseMipLevel + subresources.numMipLevels; mipLevel++)
        {
            TextureSubresourceSet currentMipSlice = TextureSubresourceSet(mipLevel, 1, subresources.baseArraySlice, subresources.numArraySlices);

            ID3D11DepthStencilView* dsv = texture.getDSV(currentMipSlice);

            if (dsv != null)
            {
                UINT clearFlags = 0;
                if (clearDepth)   clearFlags |= (.)D3D11_CLEAR_FLAG.D3D11_CLEAR_DEPTH;
                if (clearStencil) clearFlags |= (.)D3D11_CLEAR_FLAG.D3D11_CLEAR_STENCIL;
                m_Context.immediateContext.ClearDepthStencilView(dsv, clearFlags, depth, stencil);
            }
        }
    }
    
    public override void clearTextureUInt(ITexture _texture, TextureSubresourceSet subresources, uint32 clearColor)
    {
		var subresources;
        Texture texture = checked_cast<Texture, ITexture>(_texture);

#if DEBUG
        readonly ref FormatInfo formatInfo = ref getFormatInfo(texture.desc.format);
        Runtime.Assert(!formatInfo.hasDepth && !formatInfo.hasStencil);
        Runtime.Assert(texture.desc.isUAV || texture.desc.isRenderTarget);
#endif

        subresources = subresources.resolve(texture.desc, false);

        for (MipLevel mipLevel = subresources.baseMipLevel; mipLevel < subresources.baseMipLevel + subresources.numMipLevels; mipLevel++)
        {
            TextureSubresourceSet currentMipSlice = TextureSubresourceSet(mipLevel, 1, subresources.baseArraySlice, subresources.numArraySlices);

            if (texture.desc.isUAV)
            {
                ID3D11UnorderedAccessView* uav = texture.getUAV(Format.UNKNOWN, currentMipSlice, TextureDimension.Unknown);

                uint32[4] clearValues = .( clearColor, clearColor, clearColor, clearColor );
                m_Context.immediateContext.ClearUnorderedAccessViewUint(uav, &clearValues);
            }
            else if (texture.desc.isRenderTarget)
            {
                ID3D11RenderTargetView* rtv = texture.getRTV(Format.UNKNOWN, currentMipSlice);

                float[4] clearValues = .( float(clearColor), float(clearColor), float(clearColor), float(clearColor) );
                m_Context.immediateContext.ClearRenderTargetView(rtv, &clearValues);
            }
            else
            {
                break;
            }
        }
    }

    public override void copyTexture(ITexture _dst, TextureSlice dstSlice, ITexture _src, TextureSlice srcSlice)
    {
        Texture src = checked_cast<Texture, ITexture>(_src);
        Texture dst = checked_cast<Texture, ITexture>(_dst);

        copyTexture(dst.resource, dst.desc, dstSlice,
                    src.resource, src.desc, srcSlice);
    }
    
    public override void copyTexture(IStagingTexture _dst, TextureSlice dstSlice, ITexture _src, TextureSlice srcSlice)
    {
        Texture src = checked_cast<Texture, ITexture>(_src);
        StagingTexture dst = checked_cast<StagingTexture, IStagingTexture>(_dst);

        copyTexture(dst.texture.resource, dst.texture.desc, dstSlice,
                    src.resource, src.desc, srcSlice);
    }
    
    public override void copyTexture(ITexture _dst, TextureSlice dstSlice, IStagingTexture _src, TextureSlice srcSlice)
    {
        StagingTexture src = checked_cast<StagingTexture, IStagingTexture>(_src);
        Texture dst = checked_cast<Texture, ITexture>(_dst);

        copyTexture(dst.resource, dst.desc, dstSlice,
                    src.texture.resource, src.texture.desc, srcSlice);
    }
    
    public override void writeTexture(ITexture _dest, uint32 arraySlice, uint32 mipLevel, void* data, int rowPitch, int depthPitch)
    {
        Texture dest = checked_cast<Texture, ITexture>(_dest);

        UINT subresource = D3D11CalcSubresource(mipLevel, arraySlice, dest.desc.mipLevels);

        m_Context.immediateContext.UpdateSubresource(dest.resource, subresource, null, data, UINT(rowPitch), UINT(depthPitch));
    }
    
    public override void resolveTexture(ITexture _dest, TextureSubresourceSet dstSubresources, ITexture _src, TextureSubresourceSet srcSubresources)
    {
        Texture dest = checked_cast<Texture, ITexture>(_dest);
        Texture src = checked_cast<Texture, ITexture>(_src);

        TextureSubresourceSet dstSR = dstSubresources.resolve(dest.desc, false);
        TextureSubresourceSet srcSR = srcSubresources.resolve(src.desc, false);

        if (dstSR.numArraySlices != srcSR.numArraySlices || dstSR.numMipLevels != srcSR.numMipLevels)
            // let the validation layer handle the messages
            return;

        readonly ref DxgiFormatMapping formatMapping = ref getDxgiFormatMapping(dest.desc.format);

        for (ArraySlice arrayIndex = 0; arrayIndex < dstSR.numArraySlices; arrayIndex++)
        {
            for (MipLevel mipLevel = 0; mipLevel < dstSR.numMipLevels; mipLevel++)
            {
                uint32 dstSubresource = D3D11CalcSubresource(mipLevel + dstSR.baseMipLevel, arrayIndex + dstSR.baseArraySlice, dest.desc.mipLevels);
                uint32 srcSubresource = D3D11CalcSubresource(mipLevel + srcSR.baseMipLevel, arrayIndex + srcSR.baseArraySlice, src.desc.mipLevels);
                m_Context.immediateContext.ResolveSubresource(dest.resource, dstSubresource, src.resource, srcSubresource, formatMapping.rtvFormat);
            }
        }
    }

    public override void writeBuffer(IBuffer _buffer, void* data, int dataSize, uint64 destOffsetBytes)
    {
        Buffer buffer = checked_cast<Buffer, IBuffer>(_buffer);

        Runtime.Assert(destOffsetBytes + (.)dataSize <= uint32.MaxValue);

        if (buffer.desc.cpuAccess == CpuAccessMode.Write)
        {
            // we can map if it it's D3D11_USAGE_DYNAMIC, but not UpdateSubresource
            D3D11_MAPPED_SUBRESOURCE mappedData = .();
            D3D11_MAP mapType = .D3D11_MAP_WRITE_DISCARD;
            if (destOffsetBytes > 0 || dataSize + (.)destOffsetBytes < (.)buffer.desc.byteSize)
                mapType = .D3D11_MAP_WRITE;

            readonly HRESULT res = m_Context.immediateContext.Map(buffer.resource, 0, mapType, 0, &mappedData);
            if (FAILED(res))
            {
                String message = scope $"Map call failed for buffer {nvrhi.utils.DebugNameToString(buffer.desc.debugName)}, HRESULT = 0x{res}";
                m_Context.error(message);
                return;
            }

            Internal.MemCpy((char8*)mappedData.pData + destOffsetBytes, data, dataSize);
            m_Context.immediateContext.Unmap(buffer.resource, 0);
        }
        else
        {
            D3D11_BOX @box = .(){
				left = UINT(destOffsetBytes),
				top = 0,
				front = 0,
				right = UINT(destOffsetBytes + (.)dataSize),
				bottom = 1,
				back = 1
			};
            bool useBox = destOffsetBytes > 0 || dataSize < (.)buffer.desc.byteSize;

            m_Context.immediateContext.UpdateSubresource(buffer.resource, 0, useBox ? &@box : null, data, (UINT)dataSize, 0);
        }
    }
    
    public override void clearBufferUInt(IBuffer buffer, uint32 clearValue)
    {
        readonly ref BufferDesc bufferDesc = ref buffer.getDesc();
        ResourceType viewType = bufferDesc.structStride != 0 ? ResourceType.StructuredBuffer_UAV : ResourceType.TypedBuffer_UAV;
        ID3D11UnorderedAccessView* uav = checked_cast<Buffer, IBuffer>(buffer).getUAV(Format.UNKNOWN, EntireBuffer, viewType);

        UINT[4] clearValues = .(clearValue, clearValue, clearValue, clearValue );
        m_Context.immediateContext.ClearUnorderedAccessViewUint(uav, clearValues);
    }
    
    public override void copyBuffer(IBuffer _dest, uint64 destOffsetBytes, IBuffer _src, uint64 srcOffsetBytes, uint64 dataSizeBytes)
    {
        Buffer dest = checked_cast<Buffer, IBuffer>(_dest);
        Buffer src = checked_cast<Buffer, IBuffer>(_src);

        Runtime.Assert(destOffsetBytes + dataSizeBytes <= UINT.MaxValue);
        Runtime.Assert(srcOffsetBytes + dataSizeBytes <= UINT.MaxValue);

        //Do a 1D copy
        D3D11_BOX srcBox;
        srcBox.left = (UINT)srcOffsetBytes;
        srcBox.right = (UINT)(srcOffsetBytes + dataSizeBytes);
        srcBox.bottom = 1;
        srcBox.top = 0;
        srcBox.front = 0;
        srcBox.back = 1;
        m_Context.immediateContext.CopySubresourceRegion(dest.resource, 0, (UINT)destOffsetBytes, 0, 0, src.resource, 0, &srcBox);
    }

	private static char8[c_MaxPushConstantSize] g_PushConstantPaddingBuffer = .();

    public override void setPushConstants(void* data, int byteSize) 
    {
        if (byteSize > c_MaxPushConstantSize)
            return;

        Internal.MemCpy(&g_PushConstantPaddingBuffer, data, byteSize);

        m_Context.immediateContext.UpdateSubresource(
            m_Context.pushConstantBuffer, 0, null, 
            &g_PushConstantPaddingBuffer, 0, 0);
    }

    public override void setGraphicsState(GraphicsState state)
    {
        GraphicsPipeline pipeline = checked_cast<GraphicsPipeline, IGraphicsPipeline>(state.pipeline);
        Framebuffer framebuffer = checked_cast<Framebuffer, IFramebuffer>(state.framebuffer);

        if (m_CurrentComputeStateValid)
        {
            // If the previous operation has been a Dispatch call, there is a possibility of RT/UAV/SRV hazards.
            // Unbind everything to be sure, and to avoid checking the binding sets against each other. 
            // This only happens on switches between compute and graphics modes.

            clearState();
        }

        readonly bool updateFramebuffer = !m_CurrentGraphicsStateValid || m_CurrentFramebuffer != state.framebuffer;
        readonly bool updatePipeline = !m_CurrentGraphicsStateValid || m_CurrentGraphicsPipeline != state.pipeline;
        readonly bool updateBindings = updateFramebuffer || arraysAreDifferent(m_CurrentBindings, state.bindings);

        readonly bool updateViewports = !m_CurrentGraphicsStateValid ||
            arraysAreDifferent(m_CurrentViewports.viewports, state.viewport.viewports) ||
            arraysAreDifferent(m_CurrentViewports.scissorRects, state.viewport.scissorRects);

        readonly bool updateBlendState = !m_CurrentGraphicsStateValid || 
            pipeline.requiresBlendFactor && state.blendConstantColor != m_CurrentBlendConstantColor;
            
        readonly bool updateIndexBuffer = !m_CurrentGraphicsStateValid || m_CurrentIndexBufferBinding != state.indexBuffer;
        readonly bool updateVertexBuffers = !m_CurrentGraphicsStateValid || arraysAreDifferent(m_CurrentVertexBufferBindings, state.vertexBuffers);

        BindingSetVector setsToBind = .();
        if (updateBindings)
        {
            prepareToBindGraphicsResourceSets(state.bindings, m_CurrentGraphicsStateValid ? &m_CurrentBindings : null, m_CurrentGraphicsPipeline, state.pipeline, updateFramebuffer, ref setsToBind);
        }

        if (updateFramebuffer || checked_cast<GraphicsPipeline, IGraphicsPipeline>(m_CurrentGraphicsPipeline?.Get<IGraphicsPipeline>()).pixelShaderHasUAVs != pipeline.pixelShaderHasUAVs)
        {
            StaticVector<ID3D11RenderTargetView*, const c_MaxRenderTargets> RTVs = .();

            // Convert from RefCountPtr<T>[] to T[]
            for (readonly var RTV in ref framebuffer.RTVs)
                RTVs.PushBack(RTV);

            if (pipeline.pixelShaderHasUAVs)
            {
                m_Context.immediateContext.OMSetRenderTargetsAndUnorderedAccessViews(
                    UINT(RTVs.Count), RTVs.Ptr,
                    framebuffer.DSV,
                    D3D11_KEEP_UNORDERED_ACCESS_VIEWS, 0, null, null);
            }
            else
            {
                m_Context.immediateContext.OMSetRenderTargets(
                    UINT(RTVs.Count),RTVs.Ptr,
                    framebuffer.DSV);
            }
        }

        if (updatePipeline)
        {
            bindGraphicsPipeline(pipeline);
        }

        if (updatePipeline || updateBlendState)
        {
            float[4] blendFactor = .( state.blendConstantColor.r, state.blendConstantColor.g, state.blendConstantColor.b, state.blendConstantColor.a );
            m_Context.immediateContext.OMSetBlendState(pipeline.pBlendState, &blendFactor, D3D11_DEFAULT_SAMPLE_MASK);
        }

        if (updateBindings)
        {
            bindGraphicsResourceSets(setsToBind, state.pipeline);

            if (pipeline.pixelShaderHasUAVs)
            {
                ID3D11UnorderedAccessView*[D3D11_1_UAV_SLOT_COUNT] UAVs = .();
                static UINT[D3D11_1_UAV_SLOT_COUNT] initialCounts = .();
                uint32 minUAVSlot = D3D11_1_UAV_SLOT_COUNT;
                uint32 maxUAVSlot = 0;
                for (var _bindingSet in state.bindings)
                {
                    BindingSet bindingSet = checked_cast<BindingSet, IBindingSet>(_bindingSet);

                    if ((bindingSet.visibility & ShaderType.Pixel) == 0)
                        continue;

                    for (uint32 slot = bindingSet.minUAVSlot; slot <= bindingSet.maxUAVSlot; slot++)
                    {
                        UAVs[slot] = bindingSet.UAVs[slot];
                    }
                    minUAVSlot = Math.Min(minUAVSlot, bindingSet.minUAVSlot);
                    maxUAVSlot = Math.Max(maxUAVSlot, bindingSet.maxUAVSlot);
                }

                m_Context.immediateContext.OMSetRenderTargetsAndUnorderedAccessViews(D3D11_KEEP_RENDER_TARGETS_AND_DEPTH_STENCIL, null, null, minUAVSlot, maxUAVSlot - minUAVSlot + 1, /*sed: verify*/&UAVs[0] + minUAVSlot, &initialCounts);
            }
        }

        if (updateViewports)
        {
            DX11_ViewportState vpState = convertViewportState(state.viewport);

            if (vpState.numViewports != 0)
            {
                m_Context.immediateContext.RSSetViewports(vpState.numViewports, &vpState.viewports);
            }

            if (vpState.numScissorRects != 0)
            {
                m_Context.immediateContext.RSSetScissorRects(vpState.numScissorRects, &vpState.scissorRects);
            }
        }

#if NVRHI_D3D11_WITH_NVAPI
        bool updateSPS = m_CurrentSinglePassStereoState != pipeline.desc.renderState.singlePassStereo;

        if (updateSPS)
        {
            const SinglePassStereoState& spsState = pipeline.desc.renderState.singlePassStereo;

            NvAPI_Status Status = NvAPI_D3D_SetSinglePassStereoMode(m_Context.immediateContext, spsState.enabled ? 2 : 1, spsState.renderTargetIndexOffset, spsState.independentViewportMask);

            if (Status != NVAPI_OK)
            {
                m_Context.error("NvAPI_D3D_SetSinglePassStereoMode call failed");
            }

            m_CurrentSinglePassStereoState = spsState;
        }
#endif

        if (updateVertexBuffers)
        {
            ID3D11Buffer *[c_MaxVertexAttributes] pVertexBuffers = .();
            UINT[c_MaxVertexAttributes] pVertexBufferStrides = .();
            UINT[c_MaxVertexAttributes] pVertexBufferOffsets = .();

            readonly var inputLayout = pipeline.inputLayout;
            for (int i = 0; i < state.vertexBuffers.Count; i++)
            {
                readonly /*ref*/ VertexBufferBinding binding = /*ref*/ state.vertexBuffers[i];

                pVertexBuffers[i] = checked_cast<Buffer, IBuffer>(binding.buffer).resource;
                pVertexBufferStrides[i] = inputLayout.elementStrides[binding.slot];
                Runtime.Assert(binding.offset <= UINT.MaxValue);
                pVertexBufferOffsets[i] = UINT(binding.offset);
            }

            uint32 numVertexBuffers = m_CurrentGraphicsStateValid
                ? uint32(Math.Max(m_CurrentVertexBufferBindings.Count, state.vertexBuffers.Count))
                : c_MaxVertexAttributes;

            m_Context.immediateContext.IASetVertexBuffers(0, numVertexBuffers,
                &pVertexBuffers,
                &pVertexBufferStrides,
                &pVertexBufferOffsets);
        }

        if (updateIndexBuffer)
        {
            if (state.indexBuffer.buffer != null)
            {
                m_Context.immediateContext.IASetIndexBuffer(checked_cast<Buffer, IBuffer>(state.indexBuffer.buffer).resource,
                    getDxgiFormatMapping(state.indexBuffer.format).srvFormat,
                    state.indexBuffer.offset);
            }
            else
            {
                m_Context.immediateContext.IASetIndexBuffer(null, .DXGI_FORMAT_UNKNOWN, 0);
            }
        }

        m_CurrentIndirectBuffer = state.indirectParams;

        m_CurrentGraphicsStateValid = true;
        if (updatePipeline || updateFramebuffer || updateBindings || updateViewports || updateVertexBuffers || updateIndexBuffer || updateBlendState)
        {
            m_CurrentGraphicsPipeline = state.pipeline;
            m_CurrentFramebuffer = state.framebuffer;
            m_CurrentViewports = state.viewport;
            m_CurrentBlendConstantColor = state.blendConstantColor;

            m_CurrentBindings.Resize(state.bindings.Count);
            for(int i = 0; i < state.bindings.Count; i++)
            {
                m_CurrentBindings[i] = state.bindings[i];
            }

            m_CurrentVertexBufferBindings = state.vertexBuffers;
            m_CurrentIndexBufferBinding = state.indexBuffer;

            m_CurrentVertexBuffers.Resize(state.vertexBuffers.Count);
            for (int i = 0; i < state.vertexBuffers.Count; i++)
            {
                m_CurrentVertexBuffers[i] = state.vertexBuffers[i].buffer;
            }
            m_CurrentIndexBuffer = state.indexBuffer.buffer;
        }
    }
    
    public override void draw(DrawArguments args)
    {
        m_Context.immediateContext.DrawInstanced(args.vertexCount, args.instanceCount, args.startVertexLocation, args.startInstanceLocation);
    }
    
    public override void drawIndexed(DrawArguments args)
    {
        m_Context.immediateContext.DrawIndexedInstanced(args.vertexCount, args.instanceCount, args.startIndexLocation, (.)args.startVertexLocation, args.startInstanceLocation);
    }
    
    public override void drawIndirect(uint32 offsetBytes)
    {
        Buffer indirectParams = checked_cast<Buffer, IBuffer>(m_CurrentIndirectBuffer?.Get<IBuffer>());
        
        if (indirectParams != null) // validation layer will issue an error otherwise
        {
            m_Context.immediateContext.DrawInstancedIndirect(indirectParams.resource, offsetBytes);
        }
    }

    public override void setComputeState(ComputeState state)
    {
        ComputePipeline pso = checked_cast<ComputePipeline, IComputePipeline>(state.pipeline);

        if (m_CurrentGraphicsStateValid)
        {
            // If the previous operation has been a Draw call, there is a possibility of RT/UAV/SRV hazards.
            // Unbind everything to be sure, and to avoid checking the binding sets against each other. 
            // This only happens on switches between compute and graphics modes.

            clearState();
        }

        bool updatePipeline = !m_CurrentComputeStateValid || pso != m_CurrentComputePipeline;
        bool updateBindings = updatePipeline || arraysAreDifferent(m_CurrentBindings, state.bindings);

        if (updatePipeline) m_Context.immediateContext.CSSetShader(pso.shader, null, 0);
        if (updateBindings) bindComputeResourceSets(state.bindings, m_CurrentComputeStateValid ? &m_CurrentBindings : null);

        m_CurrentIndirectBuffer = state.indirectParams;

        if (updatePipeline || updateBindings)
        {
            m_CurrentComputePipeline = pso;

            m_CurrentBindings.Resize(state.bindings.Count);
            for (int i = 0; i < state.bindings.Count; i++)
            {
                m_CurrentBindings[i] = state.bindings[i];
            }

            m_CurrentComputeStateValid = true;
        }
    }
    
    public override void dispatch(uint32 groupsX, uint32 groupsY = 1, uint32 groupsZ = 1)
    {
        m_Context.immediateContext.Dispatch(groupsX, groupsY, groupsZ);
    }
    
    public override void dispatchIndirect(uint32 offsetBytes)
    {
        Buffer indirectParams = checked_cast<Buffer, IBuffer>(m_CurrentIndirectBuffer.Get<IBuffer>());
        
        if (indirectParams != null) // validation layer will issue an error otherwise
        {
            m_Context.immediateContext.DispatchIndirect(indirectParams.resource, (UINT)offsetBytes);
        }
    }

    public override void setMeshletState(MeshletState state)
    {
        utils.NotSupported();
    }
    
    public override void dispatchMesh(uint32 groupsX, uint32 groupsY = 1, uint32 groupsZ = 1) 
    {
        utils.NotSupported();
    }

    public override void setRayTracingState(nvrhi.rt.State state) 
    {
        utils.NotSupported();
    }
    
    public override void dispatchRays(nvrhi.rt.DispatchRaysArguments args) 
    {
        utils.NotSupported();
    }

    public override void buildBottomLevelAccelStruct(nvrhi.rt.IAccelStruct @as, nvrhi.rt.GeometryDesc* pGeometries, int numGeometries, nvrhi.rt.AccelStructBuildFlags buildFlags) 
    {
        utils.NotSupported();
    }
    
    public override void compactBottomLevelAccelStructs() 
    {
        utils.NotSupported();
    }
    
    public override void buildTopLevelAccelStruct(nvrhi.rt.IAccelStruct @as, nvrhi.rt.InstanceDesc* pInstances, int numInstances, nvrhi.rt.AccelStructBuildFlags buildFlags) 
    {
        utils.NotSupported();
    }
    
    public override void buildTopLevelAccelStructFromBuffer(nvrhi.rt.IAccelStruct @as, nvrhi.IBuffer instanceBuffer, uint64 instanceBufferOffset, int numInstances,
        nvrhi.rt.AccelStructBuildFlags buildFlags = nvrhi.rt.AccelStructBuildFlags.None) 
    {
        utils.NotSupported();
    }

    public override void beginTimerQuery(ITimerQuery _query)
{
    TimerQuery query = checked_cast<TimerQuery, ITimerQuery>(_query);

    Runtime.Assert(!query.resolved);
    m_Context.immediateContext.Begin(query.disjoint);
    m_Context.immediateContext.End(query.start);
}
    
    public override void endTimerQuery(ITimerQuery _query)
{
    TimerQuery query = checked_cast<TimerQuery, ITimerQuery>(_query);

    Runtime.Assert(!query.resolved);
    m_Context.immediateContext.End(query.end);
    m_Context.immediateContext.End(query.disjoint);
}

    // perf markers
    public override void beginMarker(char8* name)
    {
        if (m_UserDefinedAnnotation != null)
        {
            m_UserDefinedAnnotation.BeginEvent(scope String(name).ToScopedNativeWChar!());
        }
    }
    
    public override void endMarker()
    {
        if (m_UserDefinedAnnotation != null)
        {
            m_UserDefinedAnnotation.EndEvent();
        }
    }

    public override void setEnableAutomaticBarriers(bool enable) { (void)enable; }
    
    public override void setResourceStatesForBindingSet(IBindingSet bindingSet) { (void)bindingSet; }

    public override void setEnableUavBarriersForTexture(ITexture texture, bool enableBarriers)
    {
        (void)texture;

        if (enableBarriers)
            leaveUAVOverlapSection();
        else
            enterUAVOverlapSection();
    }
    
    public override void setEnableUavBarriersForBuffer(IBuffer buffer, bool enableBarriers)
    {
        (void)buffer;

        if (enableBarriers)
            leaveUAVOverlapSection();
        else
            enterUAVOverlapSection();
    }

    public override void beginTrackingTextureState(ITexture texture, TextureSubresourceSet subresources, ResourceStates stateBits) { (void)texture; (void)subresources; (void)stateBits; }
    
    public override void beginTrackingBufferState(IBuffer buffer, ResourceStates stateBits) { (void)buffer; (void)stateBits; }

    public override void setTextureState(ITexture texture, TextureSubresourceSet subresources, ResourceStates stateBits) { (void)texture; (void)subresources; (void)stateBits; }
    
    public override void setBufferState(IBuffer buffer, ResourceStates stateBits) { (void)buffer; (void)stateBits; }
    
    public override void setAccelStructState(nvrhi.rt.IAccelStruct @as, ResourceStates stateBits) { (void)@as; (void)stateBits; }

    public override void setPermanentTextureState(ITexture texture, ResourceStates stateBits) { (void)texture; (void)stateBits; }
   
    public override void setPermanentBufferState(IBuffer buffer, ResourceStates stateBits) { (void)buffer; (void)stateBits; }

    public override void commitBarriers() { }

    public override ResourceStates getTextureSubresourceState(ITexture texture, ArraySlice arraySlice, MipLevel mipLevel) { (void)texture; (void)arraySlice; (void)mipLevel; return ResourceStates.Common; }
    
    public override ResourceStates getBufferState(IBuffer buffer) { (void)buffer; return ResourceStates.Common; }

    public override IDevice getDevice() { return m_Device; }

    public override readonly ref CommandListParameters getDesc() { return ref m_Desc; }

    private Context* m_Context;

    private IDevice m_Device; // weak reference - to avoid a cyclic reference between Device and its ImmediateCommandList

    private CommandListParameters m_Desc;

    private D3D11RefCountPtr<ID3DUserDefinedAnnotation> m_UserDefinedAnnotation;

    private int32 m_NumUAVOverlapCommands = 0;

    private void enterUAVOverlapSection()
    {
#if NVRHI_D3D11_WITH_NVAPI
        if (m_NumUAVOverlapCommands == 0)
            NvAPI_D3D11_BeginUAVOverlap(m_Context.immediateContext);
#endif

        m_NumUAVOverlapCommands += 1;
    }

    private void leaveUAVOverlapSection()
    {
#if NVRHI_D3D11_WITH_NVAPI
        if (m_NumUAVOverlapCommands == 1)
            NvAPI_D3D11_EndUAVOverlap(m_Context.immediateContext);
#endif

        m_NumUAVOverlapCommands = Math.Max(0, m_NumUAVOverlapCommands - 1);
    }

    // State cache.
    // Use strong references (handles) instead of just a copy of GraphicsState etc.
    // If user code creates some object, draws using it, and releases it, a weak pointer would become invalid.
    // Using strong references in all state objects would solve this problem, but it means there will be an extra AddRef/Release cost everywhere.

    private GraphicsPipelineHandle m_CurrentGraphicsPipeline;
    private FramebufferHandle m_CurrentFramebuffer;
    private ViewportState m_CurrentViewports = .();
    private StaticVector<BindingSetHandle, const c_MaxBindingLayouts> m_CurrentBindings;
    private StaticVector<VertexBufferBinding, const c_MaxVertexAttributes> m_CurrentVertexBufferBindings;
    private IndexBufferBinding m_CurrentIndexBufferBinding = .();
    private StaticVector<BufferHandle, const c_MaxVertexAttributes> m_CurrentVertexBuffers;
    private BufferHandle m_CurrentIndexBuffer;
    private ComputePipelineHandle m_CurrentComputePipeline;
    private SinglePassStereoState m_CurrentSinglePassStereoState = .();
    private BufferHandle m_CurrentIndirectBuffer;
    private Color m_CurrentBlendConstantColor = .();
    private bool m_CurrentGraphicsStateValid = false;
    private bool m_CurrentComputeStateValid = false;

    private void copyTexture(ID3D11Resource *dst, TextureDesc dstDesc, TextureSlice dstSlice,
                                             ID3D11Resource *src, TextureDesc srcDesc, TextureSlice srcSlice)
    {
        var resolvedSrcSlice = srcSlice.resolve(srcDesc);
        var resolvedDstSlice = dstSlice.resolve(dstDesc);

        Runtime.Assert(resolvedDstSlice.width == resolvedSrcSlice.width);
        Runtime.Assert(resolvedDstSlice.height == resolvedSrcSlice.height);

        UINT srcSubresource = D3D11CalcSubresource(resolvedSrcSlice.mipLevel, resolvedSrcSlice.arraySlice, srcDesc.mipLevels);
        UINT dstSubresource = D3D11CalcSubresource(resolvedDstSlice.mipLevel, resolvedDstSlice.arraySlice, dstDesc.mipLevels);

        D3D11_BOX srcBox;
        srcBox.left = resolvedSrcSlice.x;
        srcBox.top = resolvedSrcSlice.y;
        srcBox.front = resolvedSrcSlice.z;
        srcBox.right = resolvedSrcSlice.x + resolvedSrcSlice.width;
        srcBox.bottom = resolvedSrcSlice.y + resolvedSrcSlice.height;
        srcBox.back = resolvedSrcSlice.z + resolvedSrcSlice.depth;

        m_Context.immediateContext.CopySubresourceRegion(dst,
                                       dstSubresource,
                                       resolvedDstSlice.x, resolvedDstSlice.y, resolvedDstSlice.z,
                                       src,
                                       srcSubresource,
                                       &srcBox);
    }
    
    private void bindGraphicsPipeline(GraphicsPipeline pso)
    {
        m_Context.immediateContext.IASetPrimitiveTopology(pso.primitiveTopology);
        m_Context.immediateContext.IASetInputLayout(pso.inputLayout != null ? pso.inputLayout.layout : null);

        m_Context.immediateContext.RSSetState(pso.pRS);

        m_Context.immediateContext.VSSetShader(pso.pVS, null, 0);
        m_Context.immediateContext.HSSetShader(pso.pHS, null, 0);
        m_Context.immediateContext.DSSetShader(pso.pDS, null, 0);
        m_Context.immediateContext.GSSetShader(pso.pGS, null, 0);
        m_Context.immediateContext.PSSetShader(pso.pPS, null, 0);

        m_Context.immediateContext.OMSetDepthStencilState(pso.pDepthStencilState, pso.stencilRef);
    }

	private static ID3D11Buffer*[D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT]  NullCBs= .();
	private static ID3D11ShaderResourceView*[D3D11_COMMONSHADER_INPUT_RESOURCE_SLOT_COUNT] NullSRVs = .();
	private static ID3D11SamplerState*[D3D11_COMMONSHADER_SAMPLER_SLOT_COUNT] NullSamplers = .();
	private static ID3D11UnorderedAccessView*[D3D11_PS_CS_UAV_REGISTER_COUNT] NullUAVs = .();
	private static UINT[D3D11_PS_CS_UAV_REGISTER_COUNT] NullUAVInitialCounts = .();

	[OnCompile(.TypeInit), Comptime]
	public static void Generate() 
	{
	    String[?] methods = .(
			"VSSetConstantBuffers",
			"VSSetShaderResources",
			"VSSetSamplers",
			"HSSetConstantBuffers",
			"HSSetShaderResources",
			"HSSetSamplers",
			"DSSetConstantBuffers",
			"DSSetShaderResources",
			"DSSetSamplers",
			"GSSetConstantBuffers",
			"GSSetShaderResources",
			"GSSetSamplers",
			"PSSetConstantBuffers",
			"PSSetShaderResources",
			"PSSetSamplers",
			"CSSetConstantBuffers",
			"CSSetShaderResources",
			"CSSetSamplers"
			);

		for (var method in methods)
		{
			Compiler.EmitTypeBody(typeof(Self), scope $"""
			private void D3D11_SET_ARRAY_{method}<T>(uint32 min, uint32 max, T array) where T : var
			{{
				if ((max) >= (min))
					m_Context.immediateContext.{method}(min, ((max) - (min) + 1), &(array)[min]);
			}}

			""");
		}
	}

    private void prepareToBindGraphicsResourceSets(
    BindingSetVector resourceSets, 
    StaticVector<BindingSetHandle, const c_MaxBindingLayouts>* currentResourceSets,
    IGraphicsPipeline _currentPipeline,
    IGraphicsPipeline _newPipeline, 
    bool updateFramebuffer, 
    ref BindingSetVector outSetsToBind)
{
    outSetsToBind = resourceSets;

    if (currentResourceSets != null)
    {
        Runtime.Assert(_currentPipeline != null);

        readonly GraphicsPipeline currentPipeline = checked_cast<GraphicsPipeline, IGraphicsPipeline>(_currentPipeline);
        readonly GraphicsPipeline newPipeline = checked_cast<GraphicsPipeline, IGraphicsPipeline>(_newPipeline);

        BindingSetVector setsToUnbind = .();
        
        for (readonly ref BindingSetHandle bindingSet in ref *currentResourceSets)
        {
            setsToUnbind.PushBack(bindingSet);
        }

        if (currentPipeline.shaderMask == newPipeline.shaderMask)
        {
            for (uint32 i = 0; i < uint32(outSetsToBind.Count); i++)
            {
                if (outSetsToBind[i] != null)
                    for (uint32 j = 0; j < uint32(setsToUnbind.Count); j++)
                    {
                        if (outSetsToBind[i] == setsToUnbind[j])
                        {
                            outSetsToBind[i] = null;
                            setsToUnbind[j] = null;
                            break;
                        }
                    }
            }

            if (!updateFramebuffer)
            {
                for (uint32 i = 0; i < uint32(outSetsToBind.Count); i++)
                {
                    if (outSetsToBind[i] != null)
                        for (uint32 j = 0; j < uint32(setsToUnbind.Count); j++)
                        {
                            if (setsToUnbind[j] != null && checked_cast<BindingSet, IBindingSet>(outSetsToBind[i]).isSupersetOf(checked_cast<BindingSet, IBindingSet>(setsToUnbind[j])))
                            {
                                setsToUnbind[j] = null;
                            }
                        }
                }
            }
        }

        for (IBindingSet _set in setsToUnbind)
        {
            if (_set == null)
                continue;

            BindingSet set = checked_cast<BindingSet, IBindingSet>(_set);

            ShaderType stagesToUnbind = set.visibility & currentPipeline.shaderMask;

            if ((stagesToUnbind & ShaderType.Vertex) != 0)
            {
                D3D11_SET_ARRAY_VSSetConstantBuffers(set.minConstantBufferSlot, set.maxConstantBufferSlot, NullCBs);
                D3D11_SET_ARRAY_VSSetShaderResources(set.minSRVSlot, set.maxSRVSlot, NullSRVs);
                D3D11_SET_ARRAY_VSSetSamplers(set.minSamplerSlot, set.maxSamplerSlot, NullSamplers);
            }

            if ((stagesToUnbind & ShaderType.Hull) != 0)
            {
                D3D11_SET_ARRAY_HSSetConstantBuffers(set.minConstantBufferSlot, set.maxConstantBufferSlot, NullCBs);
                D3D11_SET_ARRAY_HSSetShaderResources(set.minSRVSlot, set.maxSRVSlot, NullSRVs);
                D3D11_SET_ARRAY_HSSetSamplers(set.minSamplerSlot, set.maxSamplerSlot, NullSamplers);
            }

            if ((stagesToUnbind & ShaderType.Domain) != 0)
            {
                D3D11_SET_ARRAY_DSSetConstantBuffers(set.minConstantBufferSlot, set.maxConstantBufferSlot, NullCBs);
                D3D11_SET_ARRAY_DSSetShaderResources(set.minSRVSlot, set.maxSRVSlot, NullSRVs);
                D3D11_SET_ARRAY_DSSetSamplers(set.minSamplerSlot, set.maxSamplerSlot, NullSamplers);
            }

            if ((stagesToUnbind & ShaderType.Geometry) != 0)
            {
                D3D11_SET_ARRAY_GSSetConstantBuffers(set.minConstantBufferSlot, set.maxConstantBufferSlot, NullCBs);
                D3D11_SET_ARRAY_GSSetShaderResources(set.minSRVSlot, set.maxSRVSlot, NullSRVs);
                D3D11_SET_ARRAY_GSSetSamplers(set.minSamplerSlot, set.maxSamplerSlot, NullSamplers);
            }

            if ((stagesToUnbind & ShaderType.Pixel) != 0)
            {
                D3D11_SET_ARRAY_PSSetConstantBuffers(set.minConstantBufferSlot, set.maxConstantBufferSlot, NullCBs);
                D3D11_SET_ARRAY_PSSetShaderResources(set.minSRVSlot, set.maxSRVSlot, NullSRVs);
                D3D11_SET_ARRAY_PSSetSamplers(set.minSamplerSlot, set.maxSamplerSlot, NullSamplers);
            }
        }
    }
}

    private void bindGraphicsResourceSets(BindingSetVector setsToBind, IGraphicsPipeline newPipeline) {
		for(IBindingSet _set in setsToBind)
		{
		    if (_set == null)
		        continue;

		    BindingSet set = checked_cast<BindingSet, IBindingSet>(_set);
		    readonly GraphicsPipeline pipeline = checked_cast<GraphicsPipeline, IGraphicsPipeline>(newPipeline);

		    ShaderType stagesToBind = set.visibility & pipeline.shaderMask;

		    if ((stagesToBind & ShaderType.Vertex) != 0)
		    {
		        D3D11_SET_ARRAY_VSSetConstantBuffers(set.minConstantBufferSlot, set.maxConstantBufferSlot, set.constantBuffers);
		        D3D11_SET_ARRAY_VSSetShaderResources(set.minSRVSlot, set.maxSRVSlot, set.SRVs);
		        D3D11_SET_ARRAY_VSSetSamplers(set.minSamplerSlot, set.maxSamplerSlot, set.samplers);
		    }

		    if ((stagesToBind & ShaderType.Hull) != 0)
		    {
		        D3D11_SET_ARRAY_HSSetConstantBuffers(set.minConstantBufferSlot, set.maxConstantBufferSlot, set.constantBuffers);
		        D3D11_SET_ARRAY_HSSetShaderResources(set.minSRVSlot, set.maxSRVSlot, set.SRVs);
		        D3D11_SET_ARRAY_HSSetSamplers(set.minSamplerSlot, set.maxSamplerSlot, set.samplers);
		    }

		    if ((stagesToBind & ShaderType.Domain) != 0)
		    {
		        D3D11_SET_ARRAY_DSSetConstantBuffers(set.minConstantBufferSlot, set.maxConstantBufferSlot, set.constantBuffers);
		        D3D11_SET_ARRAY_DSSetShaderResources(set.minSRVSlot, set.maxSRVSlot, set.SRVs);
		        D3D11_SET_ARRAY_DSSetSamplers(set.minSamplerSlot, set.maxSamplerSlot, set.samplers);
		    }

		    if ((stagesToBind & ShaderType.Geometry) != 0)
		    {
		        D3D11_SET_ARRAY_GSSetConstantBuffers(set.minConstantBufferSlot, set.maxConstantBufferSlot, set.constantBuffers);
		        D3D11_SET_ARRAY_GSSetShaderResources(set.minSRVSlot, set.maxSRVSlot, set.SRVs);
		        D3D11_SET_ARRAY_GSSetSamplers(set.minSamplerSlot, set.maxSamplerSlot, set.samplers);
		    }

		    if ((stagesToBind & ShaderType.Pixel) != 0)
		    {
		        D3D11_SET_ARRAY_PSSetConstantBuffers(set.minConstantBufferSlot, set.maxConstantBufferSlot, set.constantBuffers);
		        D3D11_SET_ARRAY_PSSetShaderResources(set.minSRVSlot, set.maxSRVSlot, set.SRVs);
		        D3D11_SET_ARRAY_PSSetSamplers(set.minSamplerSlot, set.maxSamplerSlot, set.samplers);
		    }
		}
	}

    private void bindComputeResourceSets(BindingSetVector resourceSets, StaticVector<BindingSetHandle, const c_MaxBindingLayouts>* currentResourceSets)
{
    BindingSetVector setsToBind = resourceSets;

    if (currentResourceSets != null)
    {
        BindingSetVector setsToUnbind = .();

        for (readonly ref BindingSetHandle bindingSet in ref *currentResourceSets)
        {
            setsToUnbind.PushBack(bindingSet);
        }

        for (uint32 i = 0; i < uint32(setsToBind.Count); i++)
        {
            if (setsToBind[i] != null)
                for (uint32 j = 0; j < uint32(setsToUnbind.Count); j++)
                {
                    if (setsToBind[i] == setsToUnbind[j])
                    {
                        setsToBind[i] = null;
                        setsToUnbind[j] = null;
                        break;
                    }
                }
        }
        
        for (uint32 i = 0; i < uint32(setsToBind.Count); i++)
        {
            if (setsToBind[i] != null)
                for (uint32 j = 0; j < uint32(setsToUnbind.Count); j++)
                {
                    BindingSet setToBind = checked_cast<BindingSet, IBindingSet>(setsToBind[j]);
                    BindingSet setToUnbind = checked_cast<BindingSet, IBindingSet>(setsToUnbind[j]);

                    if (setToUnbind != null && setToBind.isSupersetOf(setToUnbind) && setToUnbind.maxUAVSlot < setToUnbind.minUAVSlot)
                    {
                        setsToUnbind[j] = null;
                    }
                }
        }

        for (IBindingSet _set in setsToUnbind)
        {
            if (_set == null)
                continue;

            BindingSet set = checked_cast<BindingSet, IBindingSet>(_set);

            if ((set.visibility & ShaderType.Compute) == 0)
                continue;

            D3D11_SET_ARRAY_CSSetConstantBuffers(set.minConstantBufferSlot, set.maxConstantBufferSlot, NullCBs);
            D3D11_SET_ARRAY_CSSetShaderResources(set.minSRVSlot, set.maxSRVSlot, NullSRVs);
            D3D11_SET_ARRAY_CSSetSamplers(set.minSamplerSlot, set.maxSamplerSlot, NullSamplers);

            if (set.maxUAVSlot >= set.minUAVSlot)
            {
                m_Context.immediateContext.CSSetUnorderedAccessViews(set.minUAVSlot,
                    set.maxUAVSlot - set.minUAVSlot + 1,
                    &NullUAVs,
                    &NullUAVInitialCounts);
            }
        }
    }

    for(IBindingSet _set in resourceSets)
    {
        BindingSet set = checked_cast<BindingSet, IBindingSet>(_set);

        if ((set.visibility & ShaderType.Compute) == 0)
            continue;

        D3D11_SET_ARRAY_CSSetConstantBuffers(set.minConstantBufferSlot, set.maxConstantBufferSlot, set.constantBuffers);
        D3D11_SET_ARRAY_CSSetShaderResources(set.minSRVSlot, set.maxSRVSlot, set.SRVs);
        D3D11_SET_ARRAY_CSSetSamplers(set.minSamplerSlot, set.maxSamplerSlot, set.samplers);

        if (set.maxUAVSlot >= set.minUAVSlot)
        {
            m_Context.immediateContext.CSSetUnorderedAccessViews(set.minUAVSlot,
                set.maxUAVSlot - set.minUAVSlot + 1,
                &set.UAVs[set.minUAVSlot],
                &NullUAVInitialCounts);
        }
    }
}
}